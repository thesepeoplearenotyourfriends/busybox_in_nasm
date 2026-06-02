# Roadmap

This project grows by adding familiar Linux utilities in educational difficulty order. BusyBox is useful as a source catalog for command names, but implementation here should remain original and teaching-focused.

Do **not** choose commands alphabetically. Pick from the lowest unfinished level unless a task explicitly says otherwise.

## Source layout and metadata

Keep command sources flat and obvious:

```text
src/
  echo.asm
  cat.asm
  wc.asm
  ls.asm
```

Track difficulty and teaching tags in documentation instead of source directories:

- `docs/command_index.tsv` is the compact command / level / tag index.
- `docs/commands.md` records each implemented command's supported subset, missing behavior, syscalls, manual tests, and limitations.

This keeps `src/cat.asm` easy to find while still making difficulty order reviewable.

## Difficulty levels

The levels below assume real educational implementations, not fake stubs. A tiny teaching subset can appear earlier than a full implementation if the subset is clearly documented.

### Level 00: primer / smoke-test commands

Purpose: prove the build system, `_start`, raw syscalls, argv/envp basics, simple stdout/stderr behavior, loops, and return codes.

Examples from the BusyBox catalog:

```text
arch, ascii, clear, echo, env, false, hostid, hostname, logname, nproc,
printenv, pwd, sleep, true, tty, ttysize, uname, usleep, whoami, yes
```

Current diagnostic order:

```text
true -> false -> echo -> yes -> pwd -> arch -> ascii -> clear -> uname -> env -> printenv -> sleep -> usleep -> hostname -> hostid -> logname -> nproc -> whoami -> tty -> ttysize -> cat -> head -> wc -> tee -> rev -> basename -> dirname -> which -> seq -> touch
```

### Level 01: beginner streams, strings, and simple file I/O

Purpose: introduce buffers, stdin/stdout loops, simple path handling, byte/string transforms, and basic file creation/deletion.

Examples:

```text
basename, cat, cmp, cut, dirname, dos2unix, expand, fold, fsync, head,
link, mkdir, nl, paste, rev, rmdir, seq, strings, sync, tac, tee, touch,
tr, unexpand, uniq, unix2dos, unlink, wc, which
```

First Level 01 progress: `cat`, `head`, `wc`, `tee`, `rev`, `basename`, `dirname`, `which`, `seq`, and `touch` are implemented.

Good remaining early targets after `pwd` and `cat`:

```text
mkdir, rmdir, cut, unlink, ln
```

### Level 02: lower-intermediate utilities

Purpose: add directory walking, `stat` data, file modes, permissions, time formatting, numeric parsing, checksums, option parsing, and careful non-recursive destructive operations.

Examples:

```text
base32, base64, cal, chgrp, chmod, chown, cksum, comm, cp, crc32, date,
df, du, expr, factor, getopt, hd, hexdump, ln, ls, mkfifo, mktemp, mv,
od, printf, readlink, realpath, rm, sort, split, stat, sum, tail, test,
truncate, xxd
```

For commands like `rm`, `cp`, and `mv`, start with limited non-recursive behavior and document it clearly. Recursive behavior can come later.

### Level 03: intermediate userland tools

Purpose: introduce `/proc`, signals, process IDs, UID/GID lookup, multi-file loops, hash algorithms, search algorithms, recursive traversal, child process execution, and wait status.

Examples:

```text
dd, diff, egrep, fgrep, find, free, fuser, grep, groups, id, install,
iostat, ipcrm, ipcs, kill, killall, last, logger, md5sum, mesg, more,
mpstat, nice, nohup, patch, pgrep, pidof, pkill, pmap, ps, pstree, pwdx,
renice, sha1sum, sha256sum, sha3sum, sha512sum, shuf, time, timeout,
top, tree, tsort, uptime, users, uudecode, uuencode, w, watch, who,
xargs
```

Famous commands such as `grep`, `find`, and `xargs` need explicit teaching subsets. For example, `grep` can grow from fixed substring search to simple regex-like behavior and then common options such as `-i`, `-v`, and `-n`.

### Level 04: upper-intermediate system-facing tools

Purpose: teach ioctl-heavy behavior, TTY handling, terminal modes, extended attributes, kernel/module metadata, device files, loop devices, hardware/system metadata, namespaces, and process/session control.

Examples:

```text
blkdiscard, blkid, blockdev, chattr, chroot, chrt, chvt, conspy,
deallocvt, dmesg, dumpkmap, fallocate, fatattr, fgconsole, findfs,
flock, getfattr, hdparm, hwclock, ionice, kbd_mode, less, loadfont,
loadkmap, losetup, lsattr, lsmod, lsof, lspci, lsscsi, lsusb, makedevs,
man, mknod, modinfo, mountpoint, nmeter, nologin, nsenter, openvt,
pipe_progress, reset, resize, run-parts, script, scriptreplay, setarch,
setconsole, setfattr, setfont, setkeycodes, setlogcons, setsid, showkey,
shred, stty, taskset, ts, unshare, vlock, volname, wall
```

Many require root, special devices, a real TTY, or specific kernel support. They are poor early diagnostics.

### Level 05: networking and services

Purpose: teach sockets, DNS, raw sockets, ICMP, TCP/UDP clients, daemon loops, interface/routing state, and protocol parsing.

Examples:

```text
arp, arping, brctl, chat, dhcprelay, dnsd, dnsdomainname, dumpleases,
ether-wake, fakeidentd, ftpd, ftpget, ftpput, httpd, ifconfig, ifdown,
ifenslave, ifplugd, ifup, inetd, ip, ipaddr, ipcalc, iplink, ipneigh,
iproute, iprule, iptunnel, lpd, lpq, lpr, microcom, nameif, nbd-client,
nc, netstat, nslookup, ntpd, ping, ping6, popmaildir, pscan, route, rx,
sendmail, slattach, ssl_client, tc, tcpsvd, telnet, telnetd, tftp,
tftpd, traceroute, traceroute6, tunctl, udhcpc, udhcpc6, udhcpd,
udpsvd, vconfig, wget, whois, zcip
```

Network tools are bad early diagnostics because failure can be caused by permissions, kernel config, network config, DNS, firewall behavior, missing devices, or code bugs.

### Level 06A: advanced OS/admin/boot/device tools

Purpose: privileged syscalls, password/shadow boundaries, init and service supervision, kernel module loading, mount tables, filesystem creation, block devices, flash devices, and shutdown/reboot paths.

These should be late-stage and often tested only in qemu, chroots, disposable overlays, or fake fixtures.

### Level 06B: advanced compression, archive, and package tools

Purpose: binary formats, checksums, compression algorithms, streaming decompression, archive traversal, and package metadata.

A simple `tar` reader that lists or extracts plain ustar archives can be educational earlier, but real tar/gzip/xz/package behavior belongs late.

### Level 06C: advanced languages, shells, editors, and interpreters

Purpose: parsers, interpreters, REPLs, terminal UI, line editing, regular expressions, scripting semantics, job control, shell expansion, and quoting rules.

Examples include `ash`, `awk`, `bc`, `dc`, `ed`, `hexedit`, `hush`, `mim`, `sed`, `sh`, and `vi`. Do not begin here. For `mim`, first confirm the exact BusyBox command semantics for the target BusyBox version before implementation.

## Suggested implementation batches

1. **Absolute basics:** `true`, `false`, `echo`, `yes`, `pwd`.
2. **First file and stream tools:** `cat`, `head`, `wc`, `tee`, `rev`.
3. **Path/string tools:** `basename`, `dirname`, `which`, `seq`, then `cut`.
4. **Tiny filesystem mutation:** `touch` is implemented; continue with `mkdir`, `rmdir`, `unlink`, and `ln`.
5. **First real filesystem inspection:** `stat`, `ls`, `readlink`, `realpath`, `du`.

Only after these batches should the project move toward `grep`, `find`, `ps`, networking, compression, shells, package tools, init tools, or filesystem repair tools.

## Worklog rule

A failed final validation step must not hide useful work. Deliver the branch with a clear worklog that says what was tested, what failed, what could not be tested, and which manual tests the project owner can run.
