'use client'

import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { ArrowLeft, RefreshCw, Check, X, ShieldCheck, Filter } from 'lucide-react'
import { getAllBusinesses, approveBusiness, rejectBusiness, verifyBusiness, Business } from '@/lib/api'

export default function BusinessesPage() {
  const [businesses, setBusinesses] = useState<Business[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('all')
  const [actionId, setActionId] = useState<string | null>(null)
  const router = useRouter()

  const loadBusinesses = useCallback(async () => {
    setLoading(true)
    try {
      const list = await getAllBusinesses(filter)
      setBusinesses(list)
    } catch (err) {
      console.error(err)
    } finally {
      setLoading(false)
    }
  }, [filter])

  useEffect(() => {
    const token = localStorage.getItem('admin_token')
    if (!token) {
      router.push('/login')
      return
    }
    loadBusinesses()
  }, [router, loadBusinesses])

  async function handleApprove(id: string) {
    setActionId(id)
    try {
      await approveBusiness(id, 'Approved via Businesses moderation table')
      await loadBusinesses()
    } catch {
      alert('Failed to approve business.')
    } finally {
      setActionId(null)
    }
  }

  async function handleReject(id: string) {
    const reason = prompt('Please enter rejection reason:', 'Incomplete documentation or policy violation')
    if (!reason) return
    setActionId(id)
    try {
      await rejectBusiness(id, reason)
      await loadBusinesses()
    } catch {
      alert('Failed to reject business.')
    } finally {
      setActionId(null)
    }
  }

  async function handleVerifyToggle(id: string, currentStatus: string) {
    const nextStatus = currentStatus === 'verified' ? 'rejected' : 'verified'
    setActionId(id)
    try {
      await verifyBusiness(id, nextStatus, `Verification updated to ${nextStatus}`)
      await loadBusinesses()
    } catch {
      alert('Failed to update verification status.')
    } finally {
      setActionId(null)
    }
  }

  return (
    <div className="p-6 md:p-8 bg-[#F7F8FA] min-h-screen">
      <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4 mb-6">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <Link href="/dashboard" className="text-xs text-[#2457D6] hover:underline flex items-center gap-1">
              <ArrowLeft className="h-3 w-3" /> Dashboard
            </Link>
          </div>
          <h1 className="text-2xl font-bold text-[#172033]">Businesses Moderation</h1>
          <p className="text-[#667085]">
            Review, verify, and moderate local business listings across all categories.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1 bg-white border border-[#E4E7EC] rounded-lg p-1 text-xs">
            <Filter className="h-3.5 w-3.5 text-[#667085] ml-2" />
            {(['all', 'approved', 'pending_review', 'rejected'] as const).map((s) => (
              <button
                key={s}
                onClick={() => setFilter(s)}
                className={`px-3 py-1.5 rounded-md font-medium transition ${
                  filter === s
                    ? 'bg-[#2457D6] text-white shadow-sm'
                    : 'text-[#667085] hover:text-[#172033]'
                }`}
              >
                {s === 'all' ? 'All' : s === 'pending_review' ? 'Pending' : s.charAt(0).toUpperCase() + s.slice(1)}
              </button>
            ))}
          </div>
          <Button onClick={loadBusinesses} disabled={loading} variant="outline" size="sm" className="flex items-center gap-1.5">
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} /> Refresh
          </Button>
        </div>
      </div>

      <Card className="border-[#E4E7EC] shadow-sm">
        <CardHeader className="pb-4">
          <CardTitle className="text-sm font-semibold">
            {filter === 'all' ? 'All listings' : `${filter.replace('_', ' ')} listings`} ({businesses.length})
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="py-16 text-center text-sm text-[#667085]">
              Loading business listings...
            </div>
          ) : businesses.length === 0 ? (
            <div className="py-16 text-center text-sm text-[#667085]">
              No businesses found for this filter.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm text-left border-collapse">
                <thead>
                  <tr className="border-b border-[#E4E7EC] text-[#667085]">
                    <th className="p-4 font-medium text-left">Business Name</th>
                    <th className="p-4 font-medium text-left">Category</th>
                    <th className="p-4 font-medium text-left">Location</th>
                    <th className="p-4 font-medium text-left">Phone</th>
                    <th className="p-4 font-medium text-left">Status</th>
                    <th className="p-4 font-medium text-left">Verification</th>
                    <th className="p-4 font-medium text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {businesses.map((b) => (
                    <tr key={b.id} className="border-b border-[#E4E7EC] hover:bg-[#F9FAFB] transition">
                      <td className="p-4 font-medium text-[#172033]">
                        <div>{b.name}</div>
                        {b.slug && <div className="text-xs text-[#667085] font-mono">/{b.slug}</div>}
                      </td>
                      <td className="p-4 text-[#667085]">
                        <span className="capitalize">{b.category_name || b.category_slug}</span>
                      </td>
                      <td className="p-4 text-[#667085]">
                        <div>{b.address_text}</div>
                        {b.city && <div className="text-xs text-[#667085]">{b.city}</div>}
                      </td>
                      <td className="p-4 text-[#667085] font-mono text-xs">
                        {b.phone_e164 || '—'}
                      </td>
                      <td className="p-4">
                        <Badge
                          variant={
                            b.status === 'approved'
                              ? 'default'
                              : b.status === 'rejected'
                              ? 'destructive'
                              : 'outline'
                          }
                        >
                          {b.status}
                        </Badge>
                      </td>
                      <td className="p-4">
                        <Badge
                          variant={
                            b.verification_status === 'verified'
                              ? 'default'
                              : b.verification_status === 'rejected'
                              ? 'destructive'
                              : 'outline'
                          }
                        >
                          {b.verification_status}
                        </Badge>
                      </td>
                      <td className="p-4 text-right">
                        <div className="flex items-center justify-end gap-1.5">
                          {b.status !== 'approved' && (
                            <Button
                              variant="default"
                              size="sm"
                              className="h-8 px-2.5 text-xs bg-[#15803D] hover:bg-[#166534]"
                              disabled={actionId === b.id}
                              onClick={() => handleApprove(b.id)}
                              title="Approve listing"
                            >
                              <Check className="h-3.5 w-3.5 mr-1" /> Approve
                            </Button>
                          )}
                          {b.status !== 'rejected' && (
                            <Button
                              variant="outline"
                              size="sm"
                              className="h-8 px-2.5 text-xs text-[#B42318] hover:bg-[#FDECEA] border-[#FDA29B]"
                              disabled={actionId === b.id}
                              onClick={() => handleReject(b.id)}
                              title="Reject listing"
                            >
                              <X className="h-3.5 w-3.5 mr-1" /> Reject
                            </Button>
                          )}
                          <Button
                            variant="outline"
                            size="sm"
                            className={`h-8 px-2.5 text-xs ${
                              b.verification_status === 'verified'
                                ? 'text-[#B42318] hover:bg-[#FDECEA]'
                                : 'text-[#2457D6] hover:bg-[#E3EEFF]'
                            }`}
                            disabled={actionId === b.id}
                            onClick={() => handleVerifyToggle(b.id, b.verification_status)}
                            title="Toggle verification badge"
                          >
                            <ShieldCheck className="h-3.5 w-3.5 mr-1" />
                            {b.verification_status === 'verified' ? 'Revoke' : 'Verify'}
                          </Button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
        <CardFooter className="flex justify-between items-center text-xs text-[#667085] pt-4">
          <div>Showing {businesses.length} records</div>
          <div className="text-xs">All actions are recorded in the audit trail.</div>
        </CardFooter>
      </Card>
    </div>
  )
}
