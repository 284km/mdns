# Notes from building mdns

## A capability that genuinely did not exist: UDP (added upstream, v0.1.62)

mkv used the server side of the TCP FFI, mhttp the client side — but
both are stream sockets. A DNS resolver needs datagrams, and there was
no UDP path at all: no `udp_*` extern, nothing emitting `SOCK_DGRAM`.
So unlike most recent dogfoods (which surfaced *bugs* in existing
capabilities), this one forced a genuinely new one.

The addition was small because the surrounding machinery already
existed. `udp_open` mirrors `tcp_connect` but with `SOCK_DGRAM`, and a
*connected* UDP socket lets `udp_send` / `udp_recv` work without passing
a peer address on every call — so they are the same shape as
`tcp_write` / `tcp_read`, reading and writing the flat arena at a given
offset. `tcp_close` and `tcp_set_timeout` turned out to be
protocol-agnostic (they operate on any fd), so they were reused as-is.

## A one-character-class papercut: extern arity

The only friction writing the program was self-inflicted: `mem_get_u16be`
takes two arguments (pointer, offset) but was declared `extern fn
mem_get_u16be: int -> int -> int -> int` (three). Because Mere is
curried, the two-argument call then had type `int -> int`, and using it
as an `int` produced "expected (int -> int), got int" — an accurate but
one-step-removed error. An `extern` block is an unchecked assertion about
the C side; getting the arrow count wrong is the FFI equivalent of a
mismatched header. Worth noting that the type system caught it at the
use site rather than letting a wrong-arity C call through.
