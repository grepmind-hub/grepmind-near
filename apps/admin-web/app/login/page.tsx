'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { Mail, Lock, ArrowRight } from 'lucide-react'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { api } from '@/lib/api'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const router = useRouter()

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      // MVP stub: authenticate against /api/v1/auth/otp/verify is OTP-based.
      // For admin portal we accept credentials and set a session token.
      await api.post('/admin/session', { email, password })
      setLoading(false)
      router.push('/dashboard')
    } catch (err: any) {
      setLoading(false)
      setError(
        err?.response?.data?.error?.message ?? 'Invalid email or password.',
      )
    }
  }

  return (
    <div className="flex min-h-screen w-full items-center justify-center bg-[#F7F8FA] px-4">
      <Card className="w-full max-w-md shadow-lg border border-[#E4E7EC]">
        <CardHeader className="text-center space-y-1">
          <CardTitle className="text-2xl">Admin Sign In</CardTitle>
          <CardDescription>
            Grepmind Near platform operations
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <div className="flex items-center gap-2 text-xs text-[#667085]">
                <Mail className="h-3 w-3" />
                <label>Email address</label>
              </div>
              <Input
                type="email"
                placeholder="admin@grepmind.local"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                className="h-11"
              />
            </div>
            <div className="space-y-2">
              <div className="flex items-center gap-2 text-xs text-[#667085]">
                <Lock className="h-3 w-3" />
                <label>Password</label>
              </div>
              <Input
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                className="h-11"
              />
            </div>
            {error && (
              <div className="rounded-md bg-[#FDECEA] p-3 text-xs text-[#B42318]">
                {error}
              </div>
            )}
            <Button type="submit" className="w-full h-11" disabled={loading}>
              {loading ? <ArrowRight className="h-4 w-4 animate-spin" /> : 'Sign in'}
            </Button>
          </form>
          <p className="text-xs text-center text-[#667085]">
            OTP-based authentication is enforced on the API. Admin session is
            a development stub.
          </p>
        </CardContent>
        <CardFooter className="flex justify-center gap-2 pt-4">
          <Link href="/" className="text-sm text-[#667085] hover:text-[#2457D6]">
            Back to customer app
          </Link>
        </CardFooter>
      </Card>
    </div>
  )
}
