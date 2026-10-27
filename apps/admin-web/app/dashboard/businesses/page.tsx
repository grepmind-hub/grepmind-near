import Link from 'next/link'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Search, Filter, Plus } from 'lucide-react'

export default function BusinessesPage() {
  return (
    <div className="p-6 md:p-8 bg-[#F7F8FA] min-h-screen">
      <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-[#172033]">Businesses</h1>
          <p className="text-[#667085]">
            Review and moderate business listings across all categories.
          </p>
        </div>
        <div className="flex gap-3">
          <Link href="/dashboard" className="flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-md text-[#667085] hover:bg-[#F2F4F7] hover:text-[#172033]">
            <Search className="h-4 w-4" /> Search
          </Link>
          <Button>New listing</Button>
        </div>
      </div>

      <Card className="border-[#E4E7EC] shadow-sm">
        <CardHeader className="pb-4">
          <CardTitle className="text-sm font-semibold">All listings</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full text-sm text-left border-collapse">
              <thead>
                <tr className="border-b border-[#E4E7EC] text-[#667085]">
                  <th className="p-4 font-medium text-left">Business</th>
                  <th className="p-4 font-medium text-left">Category</th>
                  <th className="p-4 font-medium text-left">Location</th>
                  <th className="p-4 font-medium text-left">Status</th>
                  <th className="p-4 font-medium text-left">Verification</th>
                  <th className="p-4 font-medium text-left">Actions</th>
                </tr>
              </thead>
              <tbody>
                {[1, 2, 3, 4, 5].map((i) => (
                  <TableRow key={i}>
                    <TableCell className="p-4 font-medium text-[#172033]">
                      Shree Hardware &amp; Electricals {i}
                    </TableCell>
                    <TableCell className="p-4 text-[#667085]">Hardware</TableCell>
                    <TableCell className="p-4 text-[#667085]">Unit 3, Bhubaneswar</TableCell>
                    <TableCell className="p-4">
                      <Badge variant="default">Approved</Badge>
                    </TableCell>
                    <TableCell className="p-4">
                      <Badge variant="default">Verified</Badge>
                    </TableCell>
                    <TableCell className="p-4">
                      <Button variant="ghost" size="sm" className="h-8">
                        View
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </tbody>
            </table>
          </div>
        </CardContent>
        <CardFooter>
          <div className="flex items-center gap-4">
            <span className="text-xs text-[#667085]">Showing 1–25 of 1,240 results</span>
            <div className="ml-auto flex gap-2">
              <Button variant="outline" size="sm">Previous</Button>
              <Button variant="outline" size="sm">Next</Button>
            </div>
          </div>
        </CardFooter>
      </Card>
    </div>
  )
}
