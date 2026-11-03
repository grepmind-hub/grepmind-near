'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, KeyRound, Phone, ShieldCheck } from 'lucide-react'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { api, setAuthToken } from '@/lib/api'

export default function LoginPage() {
  const [phone, setPhone] = useState('')
  const [otp, setOtp] = useState('')
  const [otpCode, setOtpCode] = useState<string | null>(null)
  const [step, setStep] = useState<'phone' | 'otp'>('phone')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const router = useRouter()

  async function requestCode(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const normalized = phone.trim().startsWith('+') ? phone.trim() : `+91${phone.trim()}`
      const res = await api.post('/auth/otp/request', { phone_e164: normalized })
      setPhone(normalized)
      setOtpCode(res.data?.data?.otp_code ?? null)
      setStep('otp')
    } catch (err: any) {
      setError(err?.response?.data?.error?.message ?? 'Could not send a verification code. Try again.')
    } finally { setLoading(false) }
  }

  async function verifyCode(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const res = await api.post('/auth/otp/verify', {
        phone_e164: phone,
        otp_code: otp,
        idempotency_key: crypto.randomUUID(),
      })
      const data = res.data?.data
      if (!data?.user?.roles?.includes('admin')) {
        if (data?.access_token) {
          await api.post('/auth/logout', {}, { headers: { Authorization: `Bearer ${data.access_token}` } }).catch(() => undefined)
        }
        setError('This account does not have administrator access.')
        return
      }
      if (!data.access_token || !data.refresh_token) {
        setError('The authentication service returned an incomplete session.')
        return
      }
      setAuthToken(data.access_token, data.refresh_token)
      router.replace('/dashboard')
    } catch (err: any) {
      setError(err?.response?.data?.error?.message ?? 'The code is invalid or expired.')
    } finally { setLoading(false) }
  }

  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[#F3F6FC] px-4 py-10">
      <div aria-hidden="true" className="pointer-events-none absolute -left-28 -top-32 h-96 w-96 rounded-full bg-blue-200/40 blur-3xl" />
      <div aria-hidden="true" className="pointer-events-none absolute -bottom-36 -right-20 h-96 w-96 rounded-full bg-teal-100/60 blur-3xl" />
      <Card className="relative w-full max-w-md rounded-3xl border border-white/80 bg-white/95 shadow-[0_24px_80px_-32px_rgba(21,48,100,.28)] backdrop-blur">
        <CardHeader className="space-y-5 px-8 pt-9 text-center">
          <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-[#2457D6] to-[#1742B3] text-white shadow-lg shadow-blue-900/20">
            <ShieldCheck className="h-7 w-7" />
          </div>
          <div className="space-y-1.5">
            <CardTitle className="text-2xl font-bold tracking-tight text-[#172033]">Admin sign in</CardTitle>
            <CardDescription className="text-sm text-[#667085]">Secure access to Grepmind Near operations</CardDescription>
          </div>
        </CardHeader>
        <CardContent className="px-8 pb-7 pt-5">
          {step === 'phone' ? (
            <form onSubmit={requestCode} className="space-y-4">
              <label className="block space-y-2 text-sm font-medium text-[#344054]">
                Administrator mobile number
                <span className="relative block">
                  <Phone className="absolute left-3.5 top-3.5 h-4 w-4 text-[#667085]" />
                  <Input autoComplete="tel" inputMode="tel" placeholder="+91 98765 43210" value={phone} onChange={(e) => setPhone(e.target.value)} required className="h-12 rounded-xl pl-10" />
                </span>
              </label>
              {error && <p role="alert" className="rounded-xl border border-rose-100 bg-rose-50 px-3.5 py-3 text-sm text-rose-700">{error}</p>}
              <Button type="submit" className="h-12 w-full rounded-xl bg-[#2457D6] text-base font-semibold hover:bg-[#1D49BD]" disabled={loading}>
                {loading ? 'Sending code…' : <>Continue securely <ArrowRight className="ml-2 h-4 w-4" /></>}
              </Button>
            </form>
          ) : (
            <form onSubmit={verifyCode} className="space-y-4">
              <div className="rounded-xl bg-[#F5F8FE] px-4 py-3 text-sm text-[#475467]">Verification code sent to <strong className="text-[#172033]">{phone}</strong></div>
              <label className="block space-y-2 text-sm font-medium text-[#344054]">
                Six-digit verification code
                <span className="relative block">
                  <KeyRound className="absolute left-3.5 top-3.5 h-4 w-4 text-[#667085]" />
                  <Input autoComplete="one-time-code" inputMode="numeric" pattern="[0-9]{6}" maxLength={6} placeholder="000000" value={otp} onChange={(e) => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))} required className="h-12 rounded-xl pl-10 text-lg tracking-[.35em]" />
                </span>
              </label>
              {otpCode && <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">Local development code: <strong>{otpCode}</strong></p>}
              {error && <p role="alert" className="rounded-xl border border-rose-100 bg-rose-50 px-3.5 py-3 text-sm text-rose-700">{error}</p>}
              <Button type="submit" className="h-12 w-full rounded-xl bg-[#2457D6] text-base font-semibold hover:bg-[#1D49BD]" disabled={loading || otp.length !== 6}>
                {loading ? 'Verifying…' : <>Verify and continue <ArrowRight className="ml-2 h-4 w-4" /></>}
              </Button>
              <button type="button" onClick={() => { setStep('phone'); setOtp(''); setError('') }} className="flex min-h-11 w-full items-center justify-center gap-2 text-sm font-medium text-[#667085] hover:text-[#2457D6]"><ArrowLeft className="h-4 w-4" /> Change mobile number</button>
            </form>
          )}
          <p className="mt-5 text-center text-xs leading-5 text-[#98A2B3]">Administrator role is checked after phone verification. Access is protected by expiring, rotating sessions.</p>
        </CardContent>
        <CardFooter className="justify-center border-t border-[#F2F4F7] px-8 py-4">
          <Link href="/" className="text-sm font-medium text-[#667085] hover:text-[#2457D6]">Back to portal</Link>
        </CardFooter>
      </Card>
    </main>
  )
}
