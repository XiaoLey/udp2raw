import socket, threading, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', 31966))
peer = [None]

def flood():
    while True:
        if peer[0]:
            try:
                s.sendto(b'F' * 64, peer[0])
            except Exception:
                pass
        time.sleep(0.005)

threading.Thread(target=flood, daemon=True).start()
while True:
    data, addr = s.recvfrom(2048)
    peer[0] = addr
    s.sendto(data, addr)
