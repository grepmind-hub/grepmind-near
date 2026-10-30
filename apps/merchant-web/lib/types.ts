export interface Business {
  id: string;
  ownerPhone?: string;
  name: string;
  category: string;
  categorySlug: string;
  locality: string;
  city: string;
  phone: string;
  rating: number;
  reviewCount: number;
  isOpen: boolean;
  isVerified: boolean;
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
  status: 'requested' | 'accepted' | 'en_route' | 'in_progress' | 'completed' | 'cancelled';
  priceEstimate?: number;
  createdAt: string;
}

export interface ProductItem {
  id: string;
  businessId: string;
  name: string;
  price: number;
  discountPrice?: number;
  category: string;
  stockCount: number;
  inStock: boolean;
  description: string;
  imageUrl?: string;
}

export interface ServiceItem {
  id: string;
  businessId: string;
  name: string;
  basePrice: number;
  durationMinutes: number;
  description: string;
  popular?: boolean;
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
  role: 'owner' | 'manager' | 'staff';
  status: 'active' | 'suspended' | 'revoked';
  createdAt: string;
}

export interface MerchantSession {
  userId: string;
  name: string;
  phone: string;
  role: 'owner' | 'manager' | 'staff';
  token: string;
}

