# mdns

A DNS resolver written in [Mere](https://merelang.org/), in pure Mere
over raw UDP — no libresolv, no getaddrinfo. It builds a DNS query
packet byte by byte, sends one datagram to a resolver, and parses the
answer section, printing A (IPv4) records as dotted quads.

```sh
mere -c mdns.mere > md.c && clang -O2 md.c -o mdns
./mdns example.com            # uses 8.8.8.8:53
./mdns github.com 1.1.1.1     # a different resolver
```

## What's implemented

- **Query construction** in the flat arena: a 12-byte header (id, the
  recursion-desired flag, one question), a QNAME as length-prefixed
  labels split on `.` and terminated by a zero byte, then QTYPE=A and
  QCLASS=IN — all written with `mem_set_u8` / `mem_set_u16be`.
- **UDP round trip** over a connected `SOCK_DGRAM` socket: `udp_open`
  resolves host:port and connects, `udp_send` writes the query datagram,
  `udp_recv` reads the response into the arena.
- **Answer parsing**: skip the echoed question, then walk ANCOUNT
  resource records — stepping past (possibly compressed) names, reading
  each record's type and length, and emitting the four IPv4 bytes of
  every A record.

Verified against `dig +short <name>` on several names and two resolvers.

## Why it exists

mdns is a dogfood — a real program written to find out where the
language rubs, and to force a missing capability. mkv and mhttp used
TCP; mdns is the first datagram-socket program, and it needed a UDP FFI
that did not exist. `udp_open` / `udp_send` / `udp_recv` were added to
the language for it (Mere v0.1.62), reusing the same flat-arena and
socket-timeout machinery as the TCP side. The wire-format work — a
binary packet built and parsed by hand — is the same shape as the gzip
block header this language's compression dogfood exercised, but over the
network instead of a file.

## Limitations

- A records (IPv4) only; no AAAA / CNAME chasing / MX / TXT.
- One question per query; no retry, no truncation-to-TCP fallback.
- Native (C backend) only — the UDP + flat-arena FFI is C-side.
