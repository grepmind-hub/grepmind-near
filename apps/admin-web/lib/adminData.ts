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
  city: 'Bhubaneswar' | 'Cuttack' | 'Puri' | 'Jajpur';
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
  city: 'Bhubaneswar' | 'Cuttack' | 'Puri' | 'Jajpur';
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
  city: 'Bhubaneswar' | 'Cuttack' | 'Puri' | 'Jajpur';
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
  totalGmv: 1845200,
  totalGmvGrowth: 14.8,
  activeListingsCount: 10,
  pendingVerificationCount: 4,
  totalRequestsCount: 10300,
  fulfillmentRatePct: 93.8,
  avgDispatchMins: 14.2,
  customerSatisfactionScore: 4.85,
};

export const DAILY_TRENDS: DailyTrendPoint[] = [
  { date: '2026-10-16', label: '16 Oct', totalRequests: 580, fulfilled: 545, cancelled: 35, gmvAmount: 104400, avgSlaMins: 15.2 },
  { date: '2026-10-17', label: '17 Oct', totalRequests: 620, fulfilled: 585, cancelled: 35, gmvAmount: 111600, avgSlaMins: 14.8 },
  { date: '2026-10-18', label: '18 Oct', totalRequests: 710, fulfilled: 668, cancelled: 42, gmvAmount: 127800, avgSlaMins: 16.1 },
  { date: '2026-10-19', label: '19 Oct', totalRequests: 690, fulfilled: 652, cancelled: 38, gmvAmount: 124200, avgSlaMins: 15.5 },
  { date: '2026-10-20', label: '20 Oct', totalRequests: 640, fulfilled: 605, cancelled: 35, gmvAmount: 115200, avgSlaMins: 14.4 },
  { date: '2026-10-21', label: '21 Oct', totalRequests: 680, fulfilled: 642, cancelled: 38, gmvAmount: 122400, avgSlaMins: 14.2 },
  { date: '2026-10-22', label: '22 Oct', totalRequests: 740, fulfilled: 698, cancelled: 42, gmvAmount: 133200, avgSlaMins: 13.9 },
  { date: '2026-10-23', label: '23 Oct', totalRequests: 790, fulfilled: 745, cancelled: 45, gmvAmount: 142200, avgSlaMins: 14.0 },
  { date: '2026-10-24', label: '24 Oct', totalRequests: 830, fulfilled: 782, cancelled: 48, gmvAmount: 149400, avgSlaMins: 13.7 },
  { date: '2026-10-25', label: '25 Oct', totalRequests: 890, fulfilled: 840, cancelled: 50, gmvAmount: 160200, avgSlaMins: 13.5 },
  { date: '2026-10-26', label: '26 Oct', totalRequests: 860, fulfilled: 812, cancelled: 48, gmvAmount: 154800, avgSlaMins: 13.8 },
  { date: '2026-10-27', label: '27 Oct', totalRequests: 910, fulfilled: 862, cancelled: 48, gmvAmount: 163800, avgSlaMins: 13.4 },
  { date: '2026-10-28', label: '28 Oct', totalRequests: 950, fulfilled: 898, cancelled: 52, gmvAmount: 171000, avgSlaMins: 13.2 },
  { date: '2026-10-29', label: 'Today', totalRequests: 1020, fulfilled: 968, cancelled: 52, gmvAmount: 183600, avgSlaMins: 12.8 },
];

export const CITY_ANALYTICS: CityAnalytics[] = [
  {
    city: 'Bhubaneswar',
    state: 'Odisha',
    activeListings: 7,
    pendingListings: 1,
    totalRequests: 5420,
    fulfilledRequests: 5160,
    fulfillmentRate: 95.2,
    gmvAmount: 975600,
    topLocalities: ['Saheed Nagar', 'Patia Infocity', 'Chandrasekharpur', 'Nayapalli'],
    unservedQueriesCount: 240,
  },
  {
    city: 'Cuttack',
    state: 'Odisha',
    activeListings: 2,
    pendingListings: 1,
    totalRequests: 2840,
    fulfilledRequests: 2640,
    fulfillmentRate: 93.0,
    gmvAmount: 511200,
    topLocalities: ['Badambadi', 'Cantonment Road', 'Mangalabag', 'Chauliaganj'],
    unservedQueriesCount: 180,
  },
  {
    city: 'Puri',
    state: 'Odisha',
    activeListings: 0,
    pendingListings: 2,
    totalRequests: 1450,
    fulfilledRequests: 1320,
    fulfillmentRate: 91.0,
    gmvAmount: 261000,
    topLocalities: ['Grand Road (Bada Danda)', 'VIP Road', 'Sea Beach Police Station', 'Chakratirtha'],
    unservedQueriesCount: 320,
  },
  {
    city: 'Jajpur',
    state: 'Odisha',
    activeListings: 1,
    pendingListings: 0,
    totalRequests: 590,
    fulfilledRequests: 520,
    fulfillmentRate: 88.1,
    gmvAmount: 97400,
    topLocalities: ['Jajpur Town Bus Stand', 'Biraja Temple Road', 'Kuakhia'],
    unservedQueriesCount: 85,
  },
];

export const CATEGORY_DEMAND: CategoryDemand[] = [
  { slug: 'electrician', name: 'Electrical & Inverters', sharePct: 32, requestsCount: 3296, avgTicket: 750, color: '#2457D6' },
  { slug: 'ac-repair', name: 'AC & Refrigeration', sharePct: 24, requestsCount: 2472, avgTicket: 1250, color: '#0F766E' },
  { slug: 'plumber', name: 'Plumbing & Motors', sharePct: 18, requestsCount: 1854, avgTicket: 580, color: '#3B82F6' },
  { slug: 'medical', name: 'Medical & Pharmacy', sharePct: 11, requestsCount: 1133, avgTicket: 620, color: '#10B981' },
  { slug: 'salon', name: 'Salon & Wellness', sharePct: 9, requestsCount: 927, avgTicket: 850, color: '#EC4899' },
  { slug: 'fashion', name: 'Handloom & Fashion', sharePct: 6, requestsCount: 618, avgTicket: 1850, color: '#F59E0B' },
];

export const HOURLY_TRENDS: HourlyTrend[] = [
  { hour: '08:00', requests: 28, slaMins: 18 },
  { hour: '09:00', requests: 64, slaMins: 16 },
  { hour: '10:00', requests: 92, slaMins: 14 },
  { hour: '11:00', requests: 88, slaMins: 14 },
  { hour: '12:00', requests: 54, slaMins: 12 },
  { hour: '13:00', requests: 42, slaMins: 13 },
  { hour: '14:00', requests: 38, slaMins: 15 },
  { hour: '15:00', requests: 48, slaMins: 14 },
  { hour: '16:00', requests: 72, slaMins: 13 },
  { hour: '17:00', requests: 104, slaMins: 12 },
  { hour: '18:00', requests: 128, slaMins: 11 },
  { hour: '19:00', requests: 118, slaMins: 12 },
  { hour: '20:00', requests: 86, slaMins: 14 },
  { hour: '21:00', requests: 52, slaMins: 16 },
  { hour: '22:00', requests: 22, slaMins: 19 },
];

export const KYC_SUBMISSIONS: KYCSubmission[] = [
  {
    id: 'kyc-001',
    businessId: 'de333333-3333-3333-3333-333333333333',
    businessName: 'Jagannath Silks & Handicrafts',
    ownerName: 'Manoj Mahapatra',
    ownerPhone: '+91 98610 00010',
    city: 'Puri',
    locality: 'Grand Road (Bada Danda)',
    category: 'Fashion & Handloom',
    coverPhotoUrl: 'http://localhost:9000/grepmind-near/biz-covers/retail_boutique.jpg',
    submittedAt: 'Today, 11:30 AM',
    status: 'pending',
    documentType: 'Artisan Board Registration',
    documentNumber: 'OD-PURI-ART-2026-912',
    gstin: '21AABCM4491N1Z3',
    issuer: 'Directorate of Textiles & Handlooms, Govt of Odisha',
    validUntil: '31 Dec 2028',
    notes: 'Submitted certified master weaver credentials and Puri Municipal Corporation Trade License.',
  },
  {
    id: 'kyc-002',
    businessId: 'de444444-4444-4444-4444-444444444444',
    businessName: 'Konark Coastal AC & Refrigeration Care',
    ownerName: 'Subrat Nayak',
    ownerPhone: '+91 98610 00011',
    city: 'Puri',
    locality: 'VIP Road, Near Sea Beach',
    category: 'Electrician & AC Care',
    coverPhotoUrl: 'http://localhost:9000/grepmind-near/biz-covers/electrical_service.jpg',
    submittedAt: 'Today, 10:15 AM',
    status: 'pending',
    documentType: 'Trade License',
    documentNumber: 'TL/PUR/2026/0491',
    gstin: '21AABCK9981M1Z2',
    issuer: 'Puri Municipality Electrical Licensing Cell',
    validUntil: '31 Mar 2027',
    notes: 'Commercial service contract license with Sea Beach hotel association.',
  },
  {
    id: 'kyc-003',
    businessId: 'ce666666-6666-6666-6666-666666666666',
    businessName: 'Barabati Diagnostics & Health Clinic',
    ownerName: 'Dr. Priyabrata Das',
    ownerPhone: '+91 98610 00012',
    city: 'Cuttack',
    locality: 'Mangalabag Medical Road',
    category: 'Medical & Pharmacy',
    coverPhotoUrl: 'http://localhost:9000/grepmind-near/biz-covers/pharmacy_store.jpg',
    submittedAt: 'Yesterday, 04:45 PM',
    status: 'pending',
    documentType: 'Clinical Establishment License',
    documentNumber: 'CTC-MED-CLINIC-7721-OD',
    gstin: '21AADCD2219K1Z5',
    issuer: 'Odisha State Health & Family Welfare Department',
    validUntil: '15 Aug 2029',
    notes: 'NABL accredited diagnostic center with registered pharmacist license attached.',
  },
  {
    id: 'kyc-004',
    businessId: 'be666666-6666-6666-6666-666666666666',
    businessName: 'Kalinga Smart Home Automation & Security',
    ownerName: 'Satyajit Rout',
    ownerPhone: '+91 98610 00013',
    city: 'Bhubaneswar',
    locality: 'Chandrasekharpur Silicon Hub',
    category: 'Electrician & Security',
    coverPhotoUrl: 'http://localhost:9000/grepmind-near/biz-covers/hardware_store.jpg',
    submittedAt: 'Yesterday, 02:10 PM',
    status: 'pending',
    documentType: 'MSME Udyam',
    documentNumber: 'UDYAM-OD-19-0028471',
    gstin: '21AABCR4412K1Z9',
    issuer: 'Ministry of MSME, Govt of India',
    validUntil: 'Lifetime / Active',
    notes: 'Certified CCTV surveillance and rooftop solar inverter installation contractor.',
  },
];

export const UNSERVED_DEMAND_ALERTS: UnservedDemandAlert[] = [
  {
    id: 'alert-001',
    city: 'Puri',
    locality: 'VIP Road & Sea Beach Road',
    query: 'Emergency AC Repair / Gas Leakage',
    searchCount: 320,
    growthPct: 42.5,
    recommendedCategory: 'Electrician / AC Repair',
    lastSearched: '15 mins ago',
  },
  {
    id: 'alert-002',
    city: 'Cuttack',
    locality: 'Chauliaganj & OMP Square',
    query: 'Water Tank Motor & Plumbing Emergency',
    searchCount: 180,
    growthPct: 28.0,
    recommendedCategory: 'Plumbing & Motors',
    lastSearched: '42 mins ago',
  },
  {
    id: 'alert-003',
    city: 'Bhubaneswar',
    locality: 'Infovalley & Gothapatna Corridor',
    query: '24x7 Electrician for Tech Campus',
    searchCount: 240,
    growthPct: 35.1,
    recommendedCategory: 'Electrician',
    lastSearched: '1 hour ago',
  },
];
