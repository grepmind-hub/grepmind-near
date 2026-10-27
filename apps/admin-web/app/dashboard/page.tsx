import Link from 'next/link'
import { Users, ShieldAlert, FileText, Clock, LayoutDashboard, LogOut } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

const stat = (title: string, value: React.ReactNode, icon: React.ReactNode, desc: string) => (
  <Card className="border-[#E4E7EC] shadow-sm">
    <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
      <CardTitle className="text-sm font-medium">{title}</CardTitle>
      <div className="text-muted-foreground">{desc}</div>
    </CardHeader>
    <CardContent>
      <div className="flex items-center gap-3">
        <span className="text-3xl font-bold">{value}</span>
        <div className="flex-1" />
        <div className="w-8 h-8 rounded-full flex items-center justify-center text-[#2457D6] bg-[#E3EEFF]">
          {icon}
        </div>
      </div>
    </CardContent>
  </Card>
)

export default function DashboardPage() {
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
            <FileText className="h-4 w-4" /> Offers
          </Link>
          <Link href="/dashboard/reports" className="flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-md text-[#667085] hover:bg-[#F2F4F7] hover:text-[#172033]">
            <FileText className="h-4 w-4" /> Reports
          </Link>
        </nav>
        <div className="p-4 border-t border-[#E4E7EC]">
          <Link
            href="/login"
            onClick={(e) => { e.preventDefault(); localStorage.removeItem('admin_token'); window.location.reload() }}
            className="flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-md text-[#B42318] hover:bg-[#FDECEA]"
          >
            <LogOut className="h-4 w-4" /> Sign out
          </Link>
        </div>
      </aside>

      {/* Main */}
      <div className="flex-1 overflow-y-auto p-6 md:p-8">
        <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold text-[#172033]">Dashboard</h1>
            <p className="text-[#667085]">
              Moderate listings, review reports, and oversee platform activity.
            </p>
          </div>
          <div className="ml-auto flex gap-3">
            <Button>Refresh</Button>
          </div>
        </div>

        <div className="mt-6 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {stat(
            'Pending verifications',
            '12',
            <Users className="h-5 w-5" />,
            'Listings awaiting review',
          )}
          {stat(
            'Reported listings',
            '3',
            <ShieldAlert className="h-5 w-5" />,
            'Needs moderator action',
          )}
          {stat(
            'Offers pending',
            '7',
            <Clock className="h-5 w-5" />,
            'Awaiting publication',
          )}
          {stat(
            'Active listings',
            '1,240',
            <LayoutDashboard className="h-5 w-5" />,
            'Approved & live',
          )}
        </div>

        <div className="mt-8 grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Pending verifications queue */}
          <Card className="col-span-1 lg:col-span-1 border-[#E4E7EC]">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-semibold">Pending verifications</CardTitle>
              <Link href="/dashboard/businesses?status=pending" className="text-xs text-[#2457D6] hover:underline">
                View all →
              </Link>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="flex items-center gap-3 p-3 rounded-lg border border-[#E4E7EC] bg-[#FFFFFF]">
                    <div className="flex-1">
                      <div className="text-sm font-medium text-[#172033]">Shree Hardware &amp; Electricals</div>
                      <div className="text-xs text-[#667085]">Hardware • Unit 3, Bhubaneswar</div>
                    </div>
                    <Badge variant="outline">Pending</Badge>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>

          {/* Recent reports */}
          <Card className="col-span-1 lg:col-span-2 border-[#E4E7EC]">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-semibold">Recent reports &amp; complaints</CardTitle>
              <Link href="/dashboard/reports" className="text-xs text-[#2457D6] hover:underline">
                View all →
              </Link>
            </CardHeader>
            <CardContent>
              <div className="overflow-x-auto">
                <table className="w-full text-sm text-left border-collapse">
                  <thead>
                    <tr className="border-b border-[#E4E7EC] text-[#667085]">
                      <th className="pb-3 font-medium text-left">Target</th>
                      <th className="pb-3 font-medium text-left">Reason</th>
                      <th className="pb-3 font-medium text-left">Status</th>
                      <th className="pb-3 font-medium text-left">Reported</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr className="border-b border-[#E4E7EC]">
                      <td className="p-3 text-[#172033] font-medium">Green Grocers</td>
                      <td className="p-3 text-[#667085]">Misleading offer expiry</td>
                      <td className="p-3"><Badge variant="outline">Open</Badge></td>
                      <td className="p-3 text-[#667085] text-xs">2h ago</td>
                    </tr>
                    <tr className="border-b border-[#E4E7EC]">
                      <td className="p-3 text-[#172033] font-medium">Quick Plumbers</td>
                      <td className="p-3 text-[#667085]">Duplicate listing</td>
                      <td className="p-3"><Badge variant="outline">Open</Badge></td>
                      <td className="p-3 text-[#667085] text-xs">5h ago</td>
                    </tr>
                    <tr>
                      <td className="p-3 text-[#172033] font-medium">City Electric</td>
                      <td className="p-3 text-[#667085]">Stale hours</td>
                      <td className="p-3"><Badge variant="secondary">Action taken</Badge></td>
                      <td className="p-3 text-[#667085] text-xs">1d ago</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  )
}
