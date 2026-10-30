import socket
import threading

def forward(src, dst, stop_event):
    try:
        while not stop_event.is_set():
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        stop_event.set()
        try:
            dst.shutdown(socket.SHUT_WR)
        except Exception:
            pass

def handle_client(client_sock):
    remote_sock = None
    try:
        remote_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_sock.connect(("127.0.0.1", 5037))
        stop_event = threading.Event()
        t1 = threading.Thread(target=forward, args=(client_sock, remote_sock, stop_event))
        t2 = threading.Thread(target=forward, args=(remote_sock, client_sock, stop_event))
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    except Exception:
        pass
    finally:
        if client_sock:
            try:
                client_sock.close()
            except Exception:
                pass
        if remote_sock:
            try:
                remote_sock.close()
            except Exception:
                pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("172.18.160.1", 5037))
    server.listen(128)
    print("TCP Bridge active on 172.18.160.1:5037 -> 127.0.0.1:5037", flush=True)
    while True:
        try:
            client_sock, _ = server.accept()
            t = threading.Thread(target=handle_client, args=(client_sock,), daemon=True)
            t.start()
        except Exception:
            break

if __name__ == "__main__":
    main()
