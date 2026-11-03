'use client'

import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { ArrowLeft, RefreshCw, History, ShieldCheck, UserCheck, AlertTriangle } from 'lucide-react'
import { getAuditLogs, AuditLog } from '@/lib/api'

export default function AuditLogsPage() {
  const [logs, setLogs] = useState<AuditLog[]>([])
  const [loading, setLoading] = useState(true)
  const router = useRouter()

  const loadLogs = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getAuditLogs()
      setLogs(data)
    } catch (err) {
      console.error(err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    let active = true
    queueMicrotask(() => {
      if (!active) return
      const token = sessionStorage.getItem('admin_access_token')
      if (!token) {
        router.push('/login')
        return
      }
      void loadLogs()
    })
    return () => { active = false }
  }, [router, loadLogs])

  const getActionBadge = (action: string) => {
    if (action.includes('approve') || action.includes('verify')) {
      return (
        <Badge variant="default" className="bg-[#15803D] hover:bg-[#166534]">
          {action}
        </Badge>
      )
    }
    if (action.includes('reject') || action.includes('dismiss')) {
      return <Badge variant="destructive">{action}</Badge>
    }
    return <Badge variant="secondary">{action}</Badge>
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
          <h1 className="text-2xl font-bold text-[#172033]">Platform Audit Trail</h1>
          <p className="text-[#667085]">
            Immutable history of administrative actions, moderation decisions, and policy enforcement.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <Button onClick={loadLogs} disabled={loading} variant="outline" size="sm" className="flex items-center gap-1.5">
            <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} /> Refresh
          </Button>
        </div>
      </div>

      <Card className="border-[#E4E7EC] shadow-sm">
        <CardHeader className="pb-4">
          <CardTitle className="text-sm font-semibold flex items-center gap-2">
            <History className="h-4 w-4 text-[#2457D6]" />
            Audit Trail ({logs.length} entries)
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="py-16 text-center text-sm text-[#667085]">
              Loading administrative audit logs...
            </div>
          ) : logs.length === 0 ? (
            <div className="py-16 text-center text-sm text-[#667085]">
              No audit logs recorded yet. Platform actions will appear here.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm text-left border-collapse">
                <thead>
                  <tr className="border-b border-[#E4E7EC] text-[#667085]">
                    <th className="p-4 font-medium text-left">Action</th>
                    <th className="p-4 font-medium text-left">Target Type</th>
                    <th className="p-4 font-medium text-left">Target ID</th>
                    <th className="p-4 font-medium text-left">Reason / Notes</th>
                    <th className="p-4 font-medium text-left">Actor</th>
                    <th className="p-4 font-medium text-left">Timestamp</th>
                  </tr>
                </thead>
                <tbody>
                  {logs.map((log) => (
                    <tr key={log.id} className="border-b border-[#E4E7EC] hover:bg-[#F9FAFB] transition">
                      <td className="p-4 font-medium">{getActionBadge(log.action)}</td>
                      <td className="p-4 text-[#172033] capitalize">{log.target_type}</td>
                      <td className="p-4 font-mono text-xs text-[#667085]">
                        {log.target_id ? `${log.target_id.slice(0, 8)}...` : '—'}
                      </td>
                      <td className="p-4 text-[#172033] max-w-md">
                        {log.reason || <span className="text-[#98A2B3] italic">No reason provided</span>}
                      </td>
                      <td className="p-4 text-xs font-mono text-[#667085]">
                        {log.actor_phone || 'admin'}
                      </td>
                      <td className="p-4 text-xs text-[#667085]">
                        {log.created_at ? new Date(log.created_at).toLocaleString() : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
        <CardFooter className="flex justify-between items-center text-xs text-[#667085] pt-4">
          <div>Showing {logs.length} logged actions</div>
          <div>Audit logs are append-only and cannot be modified.</div>
        </CardFooter>
      </Card>
    </div>
  )
}
