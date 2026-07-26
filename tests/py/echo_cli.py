import socket, sys
port = int(sys.argv[1]) if len(sys.argv) > 1 else 31967
count = int(sys.argv[2]) if len(sys.argv) > 2 else 3
payloads = [b'hello-udp2raw', b'B' * 1000, b'C' * 1400][:count]
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
ok = 0
for p in payloads:
    try:
        s.sendto(p, ('127.0.0.1', port))
        data, _ = s.recvfrom(2048)
        if data == p:
            ok += 1
    except Exception:
        pass
print(f"ECHO {ok}/{len(payloads)}")
