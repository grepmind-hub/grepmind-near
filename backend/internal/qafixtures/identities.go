package qafixtures

import (
	"errors"
	"strings"
)

// SyntheticRole represents the authorized role of a synthetic QA actor.
type SyntheticRole string

const (
	RoleMerchant SyntheticRole = "merchant"
	RoleRider    SyntheticRole = "rider"
	RoleCustomer SyntheticRole = "customer"
	RoleAdmin    SyntheticRole = "admin"
)

// SyntheticIdentitySpec defines one required test identity.
type SyntheticIdentitySpec struct {
	Key             string        `json:"key"`
	PhoneE164       string        `json:"phone_e164"`
	DisplayName     string        `json:"display_name"`
	Role            SyntheticRole `json:"role"`
	BusinessBinding string        `json:"business_binding,omitempty"`
	LocalityBinding string        `json:"locality_binding,omitempty"`
	VehicleType     string        `json:"vehicle_type,omitempty"`
	AdminDuty       string        `json:"admin_duty,omitempty"`
}

// DefaultSyntheticIdentityPlan defines the standardized 8-actor synthetic test matrix.
// Every identity uses allowlisted +9199900001XX synthetic mobile numbers.
var DefaultSyntheticIdentityPlan = []SyntheticIdentitySpec{
	{
		Key:             "merchant_a",
		PhoneE164:       "+919990000181",
		DisplayName:     "QA Merchant A (Artisanal Bakery)",
		Role:            RoleMerchant,
		BusinessBinding: "Kuanpal Artisanal Bakery Hub",
		LocalityBinding: "02200000-0000-4000-8000-000000000101",
	},
	{
		Key:             "merchant_b",
		PhoneE164:       "+919990000182",
		DisplayName:     "QA Merchant B (Fresh Organics)",
		Role:            RoleMerchant,
		BusinessBinding: "Cuttack Farm Organics Store",
		LocalityBinding: "02200000-0000-4000-8000-000000000101",
	},
	{
		Key:             "rider_a",
		PhoneE164:       "+919990000183",
		DisplayName:     "QA Rider A",
		Role:            RoleRider,
		LocalityBinding: "02200000-0000-4000-8000-000000000101",
		VehicleType:     "motorcycle",
	},
	{
		Key:             "rider_b",
		PhoneE164:       "+919990000184",
		DisplayName:     "QA Rider B",
		Role:            RoleRider,
		LocalityBinding: "02200000-0000-4000-8000-000000000101",
		VehicleType:     "electric_scooter",
	},
	{
		Key:             "customer_qa",
		PhoneE164:       "+919990000185",
		DisplayName:     "QA Verified Customer",
		Role:            RoleCustomer,
		LocalityBinding: "02200000-0000-4000-8000-000000000101",
	},
	{
		Key:         "admin_author",
		PhoneE164:   "+919990000174",
		DisplayName: "QA Admin (Author / Dispatch)",
		Role:        RoleAdmin,
		AdminDuty:   "dispatch_and_accrual_author",
	},
	{
		Key:         "admin_reviewer",
		PhoneE164:   "+919990000176",
		DisplayName: "QA Admin (Reviewer)",
		Role:        RoleAdmin,
		AdminDuty:   "settlement_and_access_reviewer",
	},
	{
		Key:         "admin_approver",
		PhoneE164:   "+919990000175",
		DisplayName: "QA Admin (Independent Approver)",
		Role:        RoleAdmin,
		AdminDuty:   "settlement_and_transfer_approver",
	},
}

// ValidateSyntheticIdentityPlan ensures the identity plan meets all security,
// multi-tenant isolation, and separation-of-duties prerequisites.
func ValidateSyntheticIdentityPlan(plan []SyntheticIdentitySpec) error {
	if len(plan) < 8 {
		return errors.New("synthetic identity plan requires at least 8 distinct actors")
	}

	seenPhones := make(map[string]string)
	seenBusinesses := make(map[string]string)
	hasMerchantA, hasMerchantB := false, false
	hasRiderA, hasRiderB := false, false
	hasCustomer := false
	adminDuties := make(map[string]string)

	for _, id := range plan {
		phone := strings.TrimSpace(id.PhoneE164)
		if !syntheticPhone.MatchString(phone) {
			return errors.New("all QA synthetic identities must use allowlisted +9199900001XX test numbers")
		}
		if existing, ok := seenPhones[phone]; ok {
			return errors.New("duplicate phone number detected across identities: " + phone + " (" + existing + " vs " + id.Key + ")")
		}
		seenPhones[phone] = id.Key

		switch id.Role {
		case RoleMerchant:
			if strings.TrimSpace(id.BusinessBinding) == "" {
				return errors.New("merchant identity must specify a distinct business binding")
			}
			if existing, ok := seenBusinesses[id.BusinessBinding]; ok {
				return errors.New("merchant business collision: " + id.BusinessBinding + " used by both " + existing + " and " + id.Key)
			}
			seenBusinesses[id.BusinessBinding] = id.Key
			if id.Key == "merchant_a" {
				hasMerchantA = true
			}
			if id.Key == "merchant_b" {
				hasMerchantB = true
			}
		case RoleRider:
			if id.Key == "rider_a" {
				hasRiderA = true
			}
			if id.Key == "rider_b" {
				hasRiderB = true
			}
		case RoleCustomer:
			hasCustomer = true
		case RoleAdmin:
			if id.AdminDuty == "" {
				return errors.New("admin identity must specify distinct administrative duty")
			}
			if existing, ok := adminDuties[id.AdminDuty]; ok {
				return errors.New("conflicting admin duties detected: " + id.AdminDuty + " (" + existing + " vs " + id.Key + ")")
			}
			adminDuties[id.AdminDuty] = id.Key
		default:
			return errors.New("unsupported role in identity plan: " + string(id.Role))
		}
	}

	if !hasMerchantA || !hasMerchantB {
		return errors.New("identity plan requires distinct Merchant A and Merchant B")
	}
	if !hasRiderA || !hasRiderB {
		return errors.New("identity plan requires distinct Rider A and Rider B")
	}
	if !hasCustomer {
		return errors.New("identity plan requires a verified Customer actor")
	}
	if len(adminDuties) < 3 {
		return errors.New("identity plan requires at least 3 distinct admin actors for separation of duties")
	}

	return nil
}
