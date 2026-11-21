package stagingenrollment

import "testing"

func TestIndividualCapabilitiesAreRandomAndValidated(t *testing.T) {
	token, digest, err := Generate()
	if err != nil { t.Fatal(err) }
	other, otherDigest, err := Generate()
	if err != nil { t.Fatal(err) }
	if token == other || digest == otherDigest { t.Fatal("capabilities must be distinct") }
	if !Matches(token, digest[:]) || Matches(other, digest[:]) { t.Fatal("capability verification failed") }
	for _, invalid := range []string{"", "short", token + "=", "%%%%"} {
		if _, err := Digest(invalid); err == nil { t.Fatal("accepted invalid capability encoding") }
	}
}
