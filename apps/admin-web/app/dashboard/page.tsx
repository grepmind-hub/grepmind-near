'use client'

import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Users, ShieldAlert, FileText, Clock, LayoutDashboard, LogOut, CheckCircle, RefreshCw, History } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { getStats, getPendingBusinesses, getReports, approveBusiness, verifyBusiness, Stats, Business, Report } from '@/lib/api'

export default function DashboardPage() {
  const [stats, setStats] = useState<Stats>({
    pending_verifications: 0,
    reported_listings: 0,
    pending_offers: 0,
    active_listings: 0,
  })
  const [pending, setPending] = useState<Business[]>([])
  const [reports, setReports] = useState<Report[]>([])
  const [loading, setLoading] = useState(true)
  const [actionLoading, setActionLoading] = useState<string | null>(null)
  const router = useRouter()

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [s, p, r] = await Promise.all([
        getStats().catch(() => ({
          pending_verifications: 0,
          reported_listings: 0,
          pending_offers: 0,
          active_listings: 0,
        })),
        getPendingBusinesses().catch(() => []),
        getReports('open').catch(() => []),
      ])
      setStats(s)
      setPending(p)
      setReports(r)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    const token = localStorage.getItem('admin_token')
    if (!token) {
      router.push('/login')
      return
    }
    loadData()
  }, [router, loadData])

  async function handleApprove(id: string) {
    setActionLoading(id)
    try {
      await approveBusiness(id, 'Approved from admin dashboard')
      await loadData()
    } catch (err) {
      alert('Failed to approve business.')
    } finally {
      setActionLoading(null)
    }
  }

  async function handleVerify(id: string) {
    setActionLoading(id)
    try {
      await verifyBusiness(id, 'verified', 'Verified from admin dashboard')
      await loadData()
    } catch (err) {
      alert('Failed to verify business.')
    } finally {
      setActionLoading(null)
    }
  }

  const statCard = (title: string, value: number, icon: React.ReactNode, desc: string) => (
    <Card className="border-[#E4E7EC] shadow-sm">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        <div className="text-xs text-muted-foreground">{desc}</div>
      </CardHeader>
      <CardContent>
        <div className="flex items-center gap-3">
          <span className="text-3xl font-bold">{loading ? '...' : value.toLocaleString()}</span>
          <div className="flex-1" />
          <div className="w-8 h-8 rounded-full flex items-center justify-center text-[#2457D6] bg-[#E3EEFF]">
            {icon}
          </div>
        </div>
      </CardContent>
    </Card>
  )

  return (
    <div className="flex h-screen overflow-hidden bg-[#F7F8FA]">
      {/* Sidebar */}
      <aside className="hidden md:flex w-64 flex-col border-r border-[#E4E7EC] bg-[#FFFFFF]">
        <div className="flex items-center gap-2 p-6">
          <div className="w-8 h-8 rounded-full flex items-center justify-center bg-[#2457D6] text-[#FFFFFF]">
            <ShieldAlert className="h-5 w-5" />
          </div>
          <span className="font-bold text-lg tracking-tight">Grepmind Admin</span>
        </div>
        <nav className="flex-1 px-4 space-y-1">
          <div className="px-3 py-2 text-xs font-semibold text-[#667085] uppercase tracking-wider">Operations</div>
          <Link href="/dashboard" className="flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-md bg-[#2457D6]/10 text-[#2457D6]">
            <LayoutDashboard className="h-4 w-4" /> Dashboard
          </Link>
          <Link href="/dashboard/businesses" className="flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-md text-[#667085] hover:bg-[#F2F4F7] hover:text-[#172033]">
            <Users className="h-4 w-4" /> Businesses
          </Link>
          <Link href="/dashboard/offers" className="flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-md text-[#667085] hover:bg-[#F2F4F7] hover:text-[#172033]">
            <Clock className="h-4 w-4" /> Offers
          </Link>
          <Link href="/dashboard/reports" className="flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-md text-[#667085] hover:bg-[#F2F4F7] hover:text-[#172033]">
            <FileText className="h-4 w-4" /> Reports
          </Link>
          <Link href="/dashboard/audit-logs" className="flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-md text-[#667085] hover:bg-[#F2F4F7] hover:text-[#172033]">
            <History className="h-4 w-4" /> Audit Logs
          </Link>
        </nav>
        <div className="p-4 border-t border-[#E4E7EC]">
          <button
            onClick={() => {
              localStorage.removeItem('admin_token')
              router.push('/login')
            }}
            className="flex w-full items-center gap-3 px-3 py-2 text-sm font-medium rounded-md text-[#B42318] hover:bg-[#FDECEA]"
          >
            <LogOut className="h-4 w-4" /> Sign out
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <div className="flex-1 overflow-y-auto p-6 md:p-8">
        <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold text-[#172033]">Admin Dashboard</h1>
            <p className="text-[#667085]">
              Moderate listings, verify merchants, review reports, and oversee platform activity.
            </p>
          </div>
          <div className="ml-auto flex gap-3">
            <Button onClick={loadData} disabled={loading} variant="outline" className="flex items-center gap-2">
              <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} /> Refresh
            </Button>
          </div>
        </div>

        <div className="mt-6 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {statCard(
            'Pending verifications',
            stats.pending_verifications,
            <Users className="h-5 w-5" />,
            'Listings awaiting review',
          )}
          {statCard(
            'Reported listings',
            stats.reported_listings,
            <ShieldAlert className="h-5 w-5" />,
            'Open user complaints',
          )}
          {statCard(
            'Offers pending',
            stats.pending_offers,
            <Clock className="h-5 w-5" />,
            'Draft/pending offers',
          )}
          {statCard(
            'Active listings',
            stats.active_listings,
            <CheckCircle className="h-5 w-5" />,
            'Approved & live shops',
          )}
        </div>

        <div className="mt-8 grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Pending verifications queue */}
          <Card className="col-span-1 lg:col-span-1 border-[#E4E7EC]">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-semibold">Pending verifications</CardTitle>
              <Link href="/dashboard/businesses?status=pending_review" className="text-xs text-[#2457D6] hover:underline">
                View all →
              </Link>
            </CardHeader>
            <CardContent>
              {pending.length === 0 ? (
                <div className="py-8 text-center text-sm text-[#667085]">
                  No pending verifications. All listings reviewed!
                </div>
              ) : (
                <div className="space-y-3">
                  {pending.slice(0, 5).map((b) => (
                    <div key={b.id} className="p-3 rounded-lg border border-[#E4E7EC] bg-[#FFFFFF] space-y-2">
                      <div className="flex items-start justify-between">
                        <div>
                          <div className="text-sm font-medium text-[#172033]">{b.name}</div>
                          <div className="text-xs text-[#667085]">{b.category_name || b.category_slug} • {b.city || 'Local'}</div>
                        </div>
                        <Badge variant="outline">{b.status}</Badge>
                      </div>
                      <div className="flex gap-2 pt-1">
                        <Button
                          size="sm"
                          variant="default"
                          className="h-7 text-xs flex-1"
                          disabled={actionLoading === b.id}
                          onClick={() => handleApprove(b.id)}
                        >
                          Approve
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-7 text-xs flex-1"
                          disabled={actionLoading === b.id}
                          onClick={() => handleVerify(b.id)}
                        >
                          Verify
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Recent reports */}
          <Card className="col-span-1 lg:col-span-2 border-[#E4E7EC]">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-semibold">Open reports &amp; complaints</CardTitle>
              <Link href="/dashboard/reports" className="text-xs text-[#2457D6] hover:underline">
                View all →
              </Link>
            </CardHeader>
            <CardContent>
              {reports.length === 0 ? (
                <div className="py-8 text-center text-sm text-[#667085]">
                  No open reports. Platform is healthy!
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-sm text-left border-collapse">
                    <thead>
                      <tr className="border-b border-[#E4E7EC] text-[#667085]">
                        <th className="pb-3 font-medium text-left">Target Type</th>
                        <th className="pb-3 font-medium text-left">Reason</th>
                        <th className="pb-3 font-medium text-left">Reporter</th>
                        <th className="pb-3 font-medium text-left">Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      {reports.slice(0, 5).map((rep) => (
                        <tr key={rep.id} className="border-b border-[#E4E7EC]">
                          <td className="p-3 text-[#172033] font-medium capitalize">{rep.target_type}</td>
                          <td className="p-3 text-[#667085]">{rep.reason}</td>
                          <td className="p-3 text-[#667085] text-xs">{rep.reporter_phone || 'Anonymous'}</td>
                          <td className="p-3">
                            <Badge variant="outline">{rep.status}</Badge>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  )
}
