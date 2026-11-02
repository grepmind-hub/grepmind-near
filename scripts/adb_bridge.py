import socket
import threading
import argparse
import os

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

def handle_client(client_sock, target):
    remote_sock = None
    try:
        remote_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_sock.connect(target)
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
    parser = argparse.ArgumentParser(description="Forward local WSL ADB traffic to the Windows ADB server")
    parser.add_argument("--bind-ip", default="127.0.0.1")
    parser.add_argument("--bind-port", type=int, default=5038)
    parser.add_argument("--target-port", type=int, default=5037)
    parser.add_argument("--target-ip", default="127.0.0.1")
    parser.add_argument("--stop-file", default="")
    args = parser.parse_args()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.bind_ip, args.bind_port))
    server.listen(128)
    server.settimeout(1)
    print(f"TCP Bridge active on {args.bind_ip}:{args.bind_port} -> {args.target_ip}:{args.target_port}", flush=True)
    while not (args.stop_file and os.path.exists(args.stop_file)):
        try:
            client_sock, _ = server.accept()
            t = threading.Thread(target=handle_client, args=(client_sock, (args.target_ip, args.target_port)), daemon=True)
            t.start()
        except socket.timeout:
            continue
        except Exception:
            break
    server.close()

if __name__ == "__main__":
    main()
