export interface Business {
  id: string;
  ownerPhone?: string;
  name: string;
  category: string;
  categorySlug: string;
  locality: string;
  city: string;
  phone: string;
  rating?: number;
  reviewCount?: number;
  isOpen: boolean;
  isVerified: boolean;
  status?: string;
  verificationStatus?: string;
  address: string;
  serviceRadiusKm: number;
  acceptsRequests: boolean;
  coverPhotoUrl?: string;
}

export interface ServiceRequest {
  id: string;
  businessId: string;
  customerName: string;
  customerPhone: string;
  serviceName: string;
  description: string;
  requestedFor: string;
  address: string;
  status: 'requested' | 'accepted' | 'in_progress' | 'rescheduled' | 'declined' | 'completed' | 'cancelled';
  priceEstimate?: number;
  createdAt: string;
}

export interface ProductItem {
  id: string;
  businessId: string;
  name: string;
  price: number;
  stockStatus: 'in_stock' | 'out_of_stock' | 'unknown';
  isPublished: boolean;
  description: string;
  imageUrl?: string;
}

export interface ServiceItem {
  id: string;
  businessId: string;
  name: string;
  basePrice: number;
  maximumPrice?: number;
  description: string;
  isActive: boolean;
}

export interface OperatingHoursDay {
  day: string;
  isOpen: boolean;
  openTime: string;
  closeTime: string;
}

export interface TeamMember {
  id: string;
  businessId: string;
  userId: string;
  name: string;
  phone: string;
  role: string;
  status: 'active' | 'suspended' | 'revoked';
  createdAt: string;
}

export interface MerchantSession {
  userId: string;
  name: string;
  phone: string;
  role: string;
  token: string;
  refreshToken?: string;
}

export interface MerchantOffer {
  id: string;
  business_id: string;
  title: string;
  description?: string;
  starts_at: string;
  ends_at: string;
  status: string;
  discount_percent?: number;
  terms?: string;
  image_url?: string;
}

