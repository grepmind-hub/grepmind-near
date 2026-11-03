'use client'

import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { ArrowLeft, RefreshCw, Check, Archive, Tag, Filter } from 'lucide-react'
import { getOffers, approveOffer, rejectOffer, Offer } from '@/lib/api'

export default function OffersPage() {
  const [offers, setOffers] = useState<Offer[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('all')
  const [actionId, setActionId] = useState<string | null>(null)
  const router = useRouter()

  const loadOffers = useCallback(async () => {
    setLoading(true)
    try {
      const list = await getOffers(filter)
      setOffers(list)
    } catch (err) {
      console.error(err)
    } finally {
      setLoading(false)
    }
  }, [filter])

  useEffect(() => {
    let active = true
    queueMicrotask(() => {
      if (!active) return
      const token = sessionStorage.getItem('admin_access_token')
      if (!token) {
        router.push('/login')
        return
      }
      void loadOffers()
    })
    return () => { active = false }
  }, [router, loadOffers])

  async function handleApprove(id: string) {
    setActionId(id)
    try {
      await approveOffer(id)
      await loadOffers()
    } catch {
      alert('Failed to approve offer.')
    } finally {
      setActionId(null)
    }
  }

  async function handleArchive(id: string) {
    setActionId(id)
    try {
      await rejectOffer(id)
      await loadOffers()
    } catch {
      alert('Failed to archive offer.')
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
          <h1 className="text-2xl font-bold text-[#172033]">Offers Moderation</h1>
          <p className="text-[#667085]">
            Moderate merchant-published promotional offers, deals, and expiry terms.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1 bg-white border border-[#E4E7EC] rounded-lg p-1 text-xs">
            <Filter className="h-3.5 w-3.5 text-[#667085] ml-2" />
            {(['all', 'published', 'draft', 'archived'] as const).map((s) => (
              <button
                key={s}
                onClick={() => setFilter(s)}
                className={`px-3 py-1.5 rounded-md font-medium transition ${
                  filter === s
                    ? 'bg-[#2457D6] text-white shadow-sm'
                    : 'text-[#667085] hover:text-[#172033]'
                }`}
              >
                {s.charAt(0).toUpperCase() + s.slice(1)}
              </button>
            ))}
          </div>
          <Button onClick={loadOffers} disabled={loading} variant="outline" size="sm" className="flex items-center gap-1.5">
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} /> Refresh
          </Button>
        </div>
      </div>

      <Card className="border-[#E4E7EC] shadow-sm">
        <CardHeader className="pb-4">
          <CardTitle className="text-sm font-semibold">
            {filter === 'all' ? 'All offers' : `${filter} offers`} ({offers.length})
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="py-16 text-center text-sm text-[#667085]">
              Loading promotional offers...
            </div>
          ) : offers.length === 0 ? (
            <div className="py-16 text-center text-sm text-[#667085]">
              No offers found for this filter.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm text-left border-collapse">
                <thead>
                  <tr className="border-b border-[#E4E7EC] text-[#667085]">
                    <th className="p-4 font-medium text-left">Offer Title</th>
                    <th className="p-4 font-medium text-left">Business</th>
                    <th className="p-4 font-medium text-left">Discount</th>
                    <th className="p-4 font-medium text-left">Valid Dates</th>
                    <th className="p-4 font-medium text-left">Status</th>
                    <th className="p-4 font-medium text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {offers.map((o) => (
                    <tr key={o.id} className="border-b border-[#E4E7EC] hover:bg-[#F9FAFB] transition">
                      <td className="p-4 font-medium text-[#172033]">
                        <div className="flex items-center gap-2">
                          <Tag className="h-4 w-4 text-[#2457D6]" />
                          <div>{o.title}</div>
                        </div>
                        {o.description && <div className="text-xs text-[#667085] mt-0.5">{o.description}</div>}
                      </td>
                      <td className="p-4 text-[#667085]">
                        {o.business_name}
                      </td>
                      <td className="p-4 text-[#15803D] font-semibold">
                        {o.discount_percent ? `${o.discount_percent}% OFF` : 'Special Promo'}
                      </td>
                      <td className="p-4 text-xs text-[#667085]">
                        <div>From: {o.starts_at ? new Date(o.starts_at).toLocaleDateString() : '—'}</div>
                        <div>To: {o.ends_at ? new Date(o.ends_at).toLocaleDateString() : '—'}</div>
                      </td>
                      <td className="p-4">
                        <Badge
                          variant={
                            o.status === 'published'
                              ? 'default'
                              : o.status === 'archived'
                              ? 'destructive'
                              : 'outline'
                          }
                        >
                          {o.status}
                        </Badge>
                      </td>
                      <td className="p-4 text-right">
                        <div className="flex items-center justify-end gap-1.5">
                          {o.status !== 'published' && (
                            <Button
                              variant="default"
                              size="sm"
                              className="h-8 px-2.5 text-xs bg-[#15803D] hover:bg-[#166534]"
                              disabled={actionId === o.id}
                              onClick={() => handleApprove(o.id)}
                            >
                              <Check className="h-3.5 w-3.5 mr-1" /> Publish
                            </Button>
                          )}
                          {o.status !== 'archived' && (
                            <Button
                              variant="outline"
                              size="sm"
                              className="h-8 px-2.5 text-xs text-[#B42318] hover:bg-[#FDECEA] border-[#FDA29B]"
                              disabled={actionId === o.id}
                              onClick={() => handleArchive(o.id)}
                            >
                              <Archive className="h-3.5 w-3.5 mr-1" /> Archive
                            </Button>
                          )}
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
          <div>Showing {offers.length} offers</div>
          <div>All moderation actions are recorded in the platform audit trail.</div>
        </CardFooter>
      </Card>
    </div>
  )
}
