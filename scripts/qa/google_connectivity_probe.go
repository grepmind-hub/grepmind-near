// Temporary read-only connectivity probe; it never sends credentials or prints proxy URLs.
package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"
)

func main() {
	for _, host := range []string{"oauth2.googleapis.com", "fcm.googleapis.com"} {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
		cancel()
		fmt.Printf("%s dns_count=%d err=%v\n", host, len(ips), err)
		conn, err := net.DialTimeout("tcp4", net.JoinHostPort(host, "443"), 5*time.Second)
		if err != nil {
			fmt.Printf("%s tcp=%v\n", host, err)
		} else {
			_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
			tlsConn := tls.Client(conn, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
			err = tlsConn.Handshake()
			fmt.Printf("%s tls=%v\n", host, err)
			_ = tlsConn.Close()
		}
		for _, mode := range []string{"direct", "environment"} {
			transport := http.DefaultTransport.(*http.Transport).Clone()
			if mode == "direct" { transport.Proxy = nil }
			client := &http.Client{Transport: transport, Timeout: 8*time.Second}
			resp, err := client.Get("https://" + host + "/")
			if err != nil { fmt.Printf("%s %s https_failed\n", host, mode) } else { fmt.Printf("%s %s http=%d\n", host, mode, resp.StatusCode); resp.Body.Close() }
			transport.CloseIdleConnections()
		}
	}
	for _, name := range []string{"HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY"} {
		fmt.Printf("%s_set=%t\n", name, os.Getenv(name) != "")
	}
}
