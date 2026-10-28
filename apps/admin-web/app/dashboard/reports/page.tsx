'use client'

import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { ArrowLeft, RefreshCw, ShieldAlert, CheckCircle, XCircle, Filter } from 'lucide-react'
import { getReports, resolveReport, Report } from '@/lib/api'

export default function ReportsPage() {
  const [reports, setReports] = useState<Report[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState('all')
  const [actionId, setActionId] = useState<string | null>(null)
  const router = useRouter()

  const loadReports = useCallback(async () => {
    setLoading(true)
    try {
      const list = await getReports(filter)
      setReports(list)
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
    loadReports()
  }, [router, loadReports])

  async function handleResolve(id: string, resolution: 'action_taken' | 'dismissed') {
    const reason = prompt(
      resolution === 'action_taken'
        ? 'Resolution notes for action taken:'
        : 'Reason for dismissal:',
      resolution === 'action_taken' ? 'Listing updated or merchant notified' : 'No violation found',
    )
    if (!reason) return
    setActionId(id)
    try {
      await resolveReport(id, resolution, reason)
      await loadReports()
    } catch {
      alert('Failed to resolve report.')
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
          <h1 className="text-2xl font-bold text-[#172033]">Reports &amp; Complaints</h1>
          <p className="text-[#667085]">
            Review user-submitted reports, inaccurate business data, and policy complaints.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1 bg-white border border-[#E4E7EC] rounded-lg p-1 text-xs">
            <Filter className="h-3.5 w-3.5 text-[#667085] ml-2" />
            {(['all', 'open', 'action_taken', 'dismissed'] as const).map((s) => (
              <button
                key={s}
                onClick={() => setFilter(s)}
                className={`px-3 py-1.5 rounded-md font-medium transition ${
                  filter === s
                    ? 'bg-[#2457D6] text-white shadow-sm'
                    : 'text-[#667085] hover:text-[#172033]'
                }`}
              >
                {s === 'all'
                  ? 'All'
                  : s === 'action_taken'
                  ? 'Action Taken'
                  : s.charAt(0).toUpperCase() + s.slice(1)}
              </button>
            ))}
          </div>
          <Button onClick={loadReports} disabled={loading} variant="outline" size="sm" className="flex items-center gap-1.5">
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} /> Refresh
          </Button>
        </div>
      </div>

      <Card className="border-[#E4E7EC] shadow-sm">
        <CardHeader className="pb-4">
          <CardTitle className="text-sm font-semibold">
            {filter === 'all' ? 'All reports' : `${filter.replace('_', ' ')} reports`} ({reports.length})
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="py-16 text-center text-sm text-[#667085]">
              Loading user reports...
            </div>
          ) : reports.length === 0 ? (
            <div className="py-16 text-center text-sm text-[#667085]">
              No reports found for this filter.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm text-left border-collapse">
                <thead>
                  <tr className="border-b border-[#E4E7EC] text-[#667085]">
                    <th className="p-4 font-medium text-left">Target</th>
                    <th className="p-4 font-medium text-left">Reason</th>
                    <th className="p-4 font-medium text-left">Reporter</th>
                    <th className="p-4 font-medium text-left">Reported Date</th>
                    <th className="p-4 font-medium text-left">Status</th>
                    <th className="p-4 font-medium text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {reports.map((rep) => (
                    <tr key={rep.id} className="border-b border-[#E4E7EC] hover:bg-[#F9FAFB] transition">
                      <td className="p-4 font-medium text-[#172033]">
                        <div className="flex items-center gap-2">
                          <ShieldAlert className="h-4 w-4 text-[#B42318]" />
                          <span className="capitalize">{rep.target_type}</span>
                        </div>
                        <div className="text-xs font-mono text-[#667085] mt-0.5">{rep.target_id.slice(0, 8)}...</div>
                      </td>
                      <td className="p-4 text-[#172033]">
                        <div>{rep.reason}</div>
                        {rep.resolution_reason && (
                          <div className="text-xs text-[#0F766E] mt-1 bg-[#F0FDFA] p-1.5 rounded border border-[#CCFBF1]">
                            Notes: {rep.resolution_reason}
                          </div>
                        )}
                      </td>
                      <td className="p-4 text-[#667085] text-xs font-mono">
                        {rep.reporter_phone || 'Anonymous'}
                      </td>
                      <td className="p-4 text-xs text-[#667085]">
                        {rep.created_at ? new Date(rep.created_at).toLocaleString() : '—'}
                      </td>
                      <td className="p-4">
                        <Badge
                          variant={
                            rep.status === 'open'
                              ? 'destructive'
                              : rep.status === 'action_taken'
                              ? 'default'
                              : 'secondary'
                          }
                        >
                          {rep.status.replace('_', ' ')}
                        </Badge>
                      </td>
                      <td className="p-4 text-right">
                        {rep.status === 'open' ? (
                          <div className="flex items-center justify-end gap-1.5">
                            <Button
                              variant="default"
                              size="sm"
                              className="h-8 px-2.5 text-xs bg-[#15803D] hover:bg-[#166534]"
                              disabled={actionId === rep.id}
                              onClick={() => handleResolve(rep.id, 'action_taken')}
                            >
                              <CheckCircle className="h-3.5 w-3.5 mr-1" /> Take Action
                            </Button>
                            <Button
                              variant="outline"
                              size="sm"
                              className="h-8 px-2.5 text-xs text-[#667085]"
                              disabled={actionId === rep.id}
                              onClick={() => handleResolve(rep.id, 'dismissed')}
                            >
                              <XCircle className="h-3.5 w-3.5 mr-1" /> Dismiss
                            </Button>
                          </div>
                        ) : (
                          <span className="text-xs text-[#667085]">Resolved</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
        <CardFooter className="flex justify-between items-center text-xs text-[#667085] pt-4">
          <div>Showing {reports.length} reports</div>
          <div>All resolution decisions are logged in the audit trail.</div>
        </CardFooter>
      </Card>
    </div>
  )
}
