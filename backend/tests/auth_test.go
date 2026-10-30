package auth

import (
	"errors"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

func TestGenerateAndValidateToken(t *testing.T) {
	secret := "test-secret-key-min-32-chars-long"

	// Create a JWT token
	claims := jwt.RegisteredClaims{
		Subject:   "test-user-id",
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
		Issuer:    "grepmind-near",
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(secret))

	if err != nil {
		t.Fatalf("Token issuance failed: %v", err)
	}

	if tokenString == "" {
		t.Fatal("Access token should not be empty")
	}

	// Parse and verify the token
	parsedToken, err := jwt.ParseWithClaims(tokenString, &jwt.RegisteredClaims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})

	if err != nil {
		t.Fatalf("Token verification failed: %v", err)
	}

	if !parsedToken.Valid {
		t.Fatal("Token should be valid")
	}

	// Use type switch to extract claims
	var claimsObj *jwt.RegisteredClaims
	switch c := parsedToken.Claims.(type) {
	case *jwt.RegisteredClaims:
		claimsObj = c
	default:
		t.Fatal("Failed to parse claims as *jwt.RegisteredClaims")
	}

	if claimsObj.Subject != "test-user-id" {
		t.Errorf("Subject mismatch: expected test-user-id, got %s", claimsObj.Subject)
	}

	if claimsObj.Issuer != "grepmind-near" {
		t.Errorf("Issuer mismatch: expected grepmind-near, got %s", claimsObj.Issuer)
	}
}

func TestJWTTokenExpiry(t *testing.T) {
	secret := "test-secret-key-min-32-chars-long"

	// Create an expired token
	claims := jwt.RegisteredClaims{
		Subject:   "expired-user",
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(-time.Hour)), // 1 hour ago
		Issuer:    "grepmind-near",
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(secret))

	if err != nil {
		t.Fatalf("Token issuance failed: %v", err)
	}

	// Verify that expired token is rejected
	_, err = jwt.ParseWithClaims(tokenString, &jwt.RegisteredClaims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(secret), nil
	})

	if err == nil {
		t.Error("Expired token should fail verification")
	}
}

func TestJWTInvalidSecret(t *testing.T) {
	secret := "test-secret-key-min-32-chars-long"
	wrongSecret := "wrong-secret"

	claims := jwt.RegisteredClaims{
		Subject:   "test-user",
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		Issuer:    "grepmind-near",
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(secret))

	if err != nil {
		t.Fatalf("Token issuance failed: %v", err)
	}

	// Try to verify with wrong secret
	_, err = jwt.ParseWithClaims(tokenString, &jwt.RegisteredClaims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(wrongSecret), nil
	})

	if err == nil {
		t.Error("Token with wrong secret should fail verification")
	}

	if !errors.Is(err, jwt.ErrTokenSignatureInvalid) {
		t.Errorf("Expected signature error, got: %v", err)
	}
}