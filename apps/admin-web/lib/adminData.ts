export interface PlatformKPIs {
  totalGmv: number;
  totalGmvGrowth: number;
  activeListingsCount: number;
  pendingVerificationCount: number;
  totalRequestsCount: number;
  fulfillmentRatePct: number;
  avgDispatchMins: number;
  customerSatisfactionScore: number;
}

export interface DailyTrendPoint {
  date: string;
  label: string;
  totalRequests: number;
  fulfilled: number;
  cancelled: number;
  gmvAmount: number;
  avgSlaMins: number;
}

export interface CityAnalytics {
  city: 'Cuttack' | 'Jajpur';
  state: string;
  activeListings: number;
  pendingListings: number;
  totalRequests: number;
  fulfilledRequests: number;
  fulfillmentRate: number;
  gmvAmount: number;
  topLocalities: string[];
  unservedQueriesCount: number;
}

export interface CategoryDemand {
  slug: string;
  name: string;
  sharePct: number;
  requestsCount: number;
  avgTicket: number;
  color: string;
}

export interface HourlyTrend {
  hour: string;
  requests: number;
  slaMins: number;
}

export interface KYCSubmission {
  id: string;
  businessId: string;
  businessName: string;
  ownerName: string;
  ownerPhone: string;
  city: 'Cuttack' | 'Jajpur';
  locality: string;
  category: string;
  coverPhotoUrl: string;
  submittedAt: string;
  status: 'pending' | 'verified' | 'rejected';
  documentType: 'Trade License' | 'Artisan Board Registration' | 'Clinical Establishment License' | 'MSME Udyam';
  documentNumber: string;
  gstin?: string;
  issuer: string;
  validUntil: string;
  notes: string;
}

export interface UnservedDemandAlert {
  id: string;
  city: 'Cuttack' | 'Jajpur';
  locality: string;
  query: string;
  searchCount: number;
  growthPct: number;
  recommendedCategory: string;
  lastSearched: string;
}

// -------------------------------------------------------------
// Realistic Seeded Datasets for Admin Analytics
// -------------------------------------------------------------

export const PLATFORM_KPIS: PlatformKPIs = {
  totalGmv: 0,
  totalGmvGrowth: 0,
  activeListingsCount: 0,
  pendingVerificationCount: 0,
  totalRequestsCount: 0,
  fulfillmentRatePct: 0,
  avgDispatchMins: 0,
  customerSatisfactionScore: 0,
};

export const DAILY_TRENDS: DailyTrendPoint[] = [];

export const CITY_ANALYTICS: CityAnalytics[] = [];

export const CATEGORY_DEMAND: CategoryDemand[] = [];

export const HOURLY_TRENDS: HourlyTrend[] = [];

export const KYC_SUBMISSIONS: KYCSubmission[] = [];

export const UNSERVED_DEMAND_ALERTS: UnservedDemandAlert[] = [];
