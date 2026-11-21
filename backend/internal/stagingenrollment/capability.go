// Package stagingenrollment implements per-installation staging authorization.
// Capabilities authorize test access; they do not establish phone ownership.
package stagingenrollment

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
)

const capabilityBytes = 32

// Generate returns a cryptographically random, individual enrollment secret
// and its digest. Only the digest should be persisted by the server.
func Generate() (string, [sha256.Size]byte, error) {
	var raw [capabilityBytes]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", [sha256.Size]byte{}, err
	}
	token := base64.RawURLEncoding.EncodeToString(raw[:])
	return token, sha256.Sum256(raw[:]), nil
}

// Digest validates the encoding and hashes the raw random capability.
func Digest(token string) ([sha256.Size]byte, error) {
	raw, err := base64.RawURLEncoding.DecodeString(token)
	if err != nil || len(raw) != capabilityBytes || base64.RawURLEncoding.EncodeToString(raw) != token {
		return [sha256.Size]byte{}, errors.New("invalid staging enrollment")
	}
	return sha256.Sum256(raw), nil
}

func Matches(token string, expected []byte) bool {
	digest, err := Digest(token)
	return err == nil && len(expected) == sha256.Size && subtle.ConstantTimeCompare(digest[:], expected) == 1
}
