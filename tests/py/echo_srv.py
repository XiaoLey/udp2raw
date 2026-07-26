import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 31966))
while True:
    data, addr = s.recvfrom(2048)
    s.sendto(data, addr)
