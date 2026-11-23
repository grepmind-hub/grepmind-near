'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Eye, EyeOff, KeyRound, Lock, Phone, ShieldCheck, User } from 'lucide-react'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { api, setAuthToken } from '@/lib/api'

function createIdempotencyKey(): string {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID()
  if (!globalThis.crypto?.getRandomValues) throw new Error('Secure randomness is unavailable.')

  const bytes = globalThis.crypto.getRandomValues(new Uint8Array(16))
  bytes[6] = (bytes[6] & 0x0f) | 0x40
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

export default function LoginPage() {
  const [authMethod, setAuthMethod] = useState<'password' | 'otp'>('password')
  
  // Password credentials state
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)

  // Phone OTP state
  const [phone, setPhone] = useState('')
  const [otp, setOtp] = useState('')
  const [challengeId, setChallengeId] = useState<string | null>(null)
  const [resendSeconds, setResendSeconds] = useState(0)
  const [step, setStep] = useState<'phone' | 'otp' | 'pin' | 'enroll'>('phone')
  const [pinEnrolled, setPINEnrolled] = useState(false)
  const [pin, setPIN] = useState('')
  const [confirmPIN, setConfirmPIN] = useState('')

  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const router = useRouter()

  useEffect(() => {
    const controller = new AbortController()
    void api.get('/auth/admin-mpin', { signal: controller.signal })
      .then(({ data }) => {
        if (controller.signal.aborted || typeof data?.data?.enabled !== 'boolean') return
        if (data.data.enabled && data.data.enrolled) {
          setPINEnrolled(true)
        }
      })
      .catch(() => undefined)
    return () => controller.abort()
  }, [])

  useEffect(() => {
    if (step !== 'otp' || resendSeconds <= 0) return
    const timer = window.setTimeout(() => setResendSeconds((value) => Math.max(0, value - 1)), 1000)
    return () => window.clearTimeout(timer)
  }, [resendSeconds, step])

  async function handlePasswordLogin(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const res = await api.post('/auth/admin-password-login', {
        username: username.trim(),
        password,
      })
      const data = res.data?.data
      if (!data?.user?.roles?.includes('admin')) {
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
      setError(err?.response?.data?.error?.message ?? 'Invalid username or password. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  async function requestCode(e: React.FormEvent) {
    e.preventDefault()
    const normalized = phone.trim().startsWith('+') ? phone.trim() : `+91${phone.trim()}`
    await requestOtp(normalized)
  }

  async function requestOtp(normalized: string) {
    setError('')
    setLoading(true)
    try {
      const res = await api.post('/auth/otp/request', { phone_e164: normalized })
      setPhone(normalized)
      setChallengeId(res.data?.data?.challenge_id ?? null)
      setOtp('')
      setStep('otp')
      setResendSeconds(60)
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
        ...(challengeId ? { challenge_id: challengeId } : {}),
        idempotency_key: createIdempotencyKey(),
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
      if (data.admin_mpin_enrollment_available === true) {
        setPIN('')
        setConfirmPIN('')
        setStep('enroll')
      } else {
        router.replace('/dashboard')
      }
    } catch (err: any) {
      setError(err?.response?.data?.error?.message ?? 'The code is invalid or expired.')
    } finally { setLoading(false) }
  }

  async function submitPIN(event: React.FormEvent) {
    event.preventDefault()
    const enrolling = step === 'enroll'
    setError('')
    if (enrolling && pin !== confirmPIN) {
      setError('The PINs must match.')
      return
    }
    setLoading(true)
    try {
      const { data } = await api.post(enrolling ? '/auth/admin-mpin/enroll' : '/auth/admin-mpin/verify', { pin })
      if (!enrolling) {
        if (!data?.data?.access_token || !data?.data?.refresh_token) throw new Error('Incomplete session')
        setAuthToken(data.data.access_token, data.data.refresh_token)
      }
      router.replace('/dashboard')
    } catch {
      setError(enrolling
        ? 'PIN setup failed. You can continue to the dashboard or sign in with OTP again to retry.'
        : 'PIN sign-in failed. Use OTP if the PIN has expired or is locked.')
    } finally {
      setPIN('')
      setConfirmPIN('')
      setLoading(false)
    }
  }

  async function removePIN() {
    setError('')
    setLoading(true)
    try {
      await api.post('/auth/admin-mpin/remove', {})
      setPINEnrolled(false)
      setPIN('')
      setConfirmPIN('')
      setStep('phone')
    } catch (err: any) {
      setError(err?.response?.data?.error?.message ?? 'PIN removal requires a recent OTP sign-in.')
    } finally { setLoading(false) }
  }

  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[#F3F6FC] px-4 py-10">
      <div aria-hidden="true" className="pointer-events-none absolute -left-28 -top-32 h-96 w-96 rounded-full bg-blue-200/40 blur-3xl" />
      <div aria-hidden="true" className="pointer-events-none absolute -bottom-36 -right-20 h-96 w-96 rounded-full bg-teal-100/60 blur-3xl" />
      <Card className="relative w-full max-w-md rounded-3xl border border-white/80 bg-white/95 shadow-[0_24px_80px_-32px_rgba(21,48,100,.28)] backdrop-blur">
        <CardHeader className="space-y-4 px-8 pt-8 text-center">
          <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-[#087F0D] text-white shadow-lg shadow-emerald-900/20">
            <ShieldCheck className="h-7 w-7" />
          </div>
          <div className="space-y-1">
            <CardTitle className="text-2xl font-bold tracking-tight text-[#172820]">Admin sign in</CardTitle>
            <CardDescription className="text-sm text-[#64748B]">Secure access to Abashyaka platform operations</CardDescription>
          </div>

          {/* Toggle between Password and Phone OTP */}
          <div className="flex rounded-xl bg-[#F1F5F9] p-1 text-sm font-semibold">
            <button
              type="button"
              onClick={() => { setAuthMethod('password'); setError(''); }}
              className={`flex-1 rounded-lg py-2 transition-all duration-200 ${
                authMethod === 'password'
                  ? 'bg-white text-[#064D3A] shadow-sm'
                  : 'text-[#64748B] hover:text-[#172820]'
              }`}
            >
              Password
            </button>
            <button
              type="button"
              onClick={() => { setAuthMethod('otp'); setError(''); }}
              className={`flex-1 rounded-lg py-2 transition-all duration-200 ${
                authMethod === 'otp'
                  ? 'bg-white text-[#064D3A] shadow-sm'
                  : 'text-[#64748B] hover:text-[#172820]'
              }`}
            >
              Mobile OTP
            </button>
          </div>
        </CardHeader>

        <CardContent className="px-8 pb-7 pt-3">
          {authMethod === 'password' ? (
            <form onSubmit={handlePasswordLogin} className="space-y-4">
              <label className="block space-y-1.5 text-sm font-medium text-[#344054]">
                Administrator username or email
                <span className="relative block">
                  <User className="absolute left-3.5 top-3.5 h-4 w-4 text-[#667085]" />
                  <Input
                    type="text"
                    autoComplete="username"
                    placeholder="admin@abashyaka.com or superadmin"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    required
                    className="h-12 rounded-xl pl-10"
                  />
                </span>
              </label>

              <label className="block space-y-1.5 text-sm font-medium text-[#344054]">
                Password
                <span className="relative block">
                  <Lock className="absolute left-3.5 top-3.5 h-4 w-4 text-[#667085]" />
                  <Input
                    type={showPassword ? 'text' : 'password'}
                    autoComplete="current-password"
                    placeholder="Enter admin password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    className="h-12 rounded-xl pl-10 pr-10"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3.5 top-3.5 text-[#667085] hover:text-[#172820]"
                    tabIndex={-1}
                  >
                    {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </span>
              </label>

              {error && (
                <p role="alert" className="rounded-xl border border-rose-100 bg-rose-50 px-3.5 py-3 text-sm text-rose-700">
                  {error}
                </p>
              )}

              <Button
                type="submit"
                className="h-12 w-full rounded-xl bg-[#087F0D] text-base font-semibold hover:bg-[#06680A]"
                disabled={loading || !username.trim() || !password}
              >
                {loading ? 'Verifying credentials…' : <>Sign in to Admin <ArrowRight className="ml-2 h-4 w-4" /></>}
              </Button>
            </form>
          ) : step === 'phone' ? (
            <form onSubmit={requestCode} className="space-y-4">
              <label className="block space-y-2 text-sm font-medium text-[#344054]">
                Administrator mobile number
                <span className="relative block">
                  <Phone className="absolute left-3.5 top-3.5 h-4 w-4 text-[#667085]" />
                  <Input autoComplete="tel" inputMode="tel" placeholder="+91 98765 43210" value={phone} onChange={(e) => setPhone(e.target.value)} required className="h-12 rounded-xl pl-10" />
                </span>
              </label>
              {error && <p role="alert" className="rounded-xl border border-rose-100 bg-rose-50 px-3.5 py-3 text-sm text-rose-700">{error}</p>}
              <Button type="submit" className="h-12 w-full rounded-xl bg-[#087F0D] text-base font-semibold hover:bg-[#06680A]" disabled={loading}>
                {loading ? 'Sending code…' : <>Continue securely <ArrowRight className="ml-2 h-4 w-4" /></>}
              </Button>
              {pinEnrolled && (
                <Button type="button" variant="outline" className="h-12 w-full" disabled={loading} onClick={() => {
                  setError('')
                  setStep('pin')
                }}>Sign in with PIN</Button>
              )}
            </form>
          ) : step === 'pin' || step === 'enroll' ? (
            <form onSubmit={submitPIN} className="space-y-4">
              {step === 'enroll' && <p className="text-sm text-[#475467]">Set a PIN to sign in again from this browser. This replaces any previous browser enrollment.</p>}
              <label className="block space-y-2 text-sm font-medium text-[#344054]">
                {step === 'enroll' ? 'New six-digit PIN' : 'Six-digit PIN'}
                <Input type="password" inputMode="numeric" autoComplete={step === 'enroll' ? 'new-password' : 'current-password'} pattern="[0-9]{6}" maxLength={6} value={pin} onChange={(event) => setPIN(event.target.value.replace(/[^0-9]/g, ''))} required className="h-12 rounded-xl" />
              </label>
              {step === 'enroll' && <label className="block space-y-2 text-sm font-medium text-[#344054]">
                Confirm PIN
                <Input type="password" inputMode="numeric" autoComplete="new-password" pattern="[0-9]{6}" maxLength={6} value={confirmPIN} onChange={(event) => setConfirmPIN(event.target.value.replace(/[^0-9]/g, ''))} required className="h-12 rounded-xl" />
              </label>}
              {error && <p role="alert" className="text-sm text-rose-700">{error}</p>}
              <Button type="submit" className="h-12 w-full rounded-xl bg-[#087F0D] hover:bg-[#06680A]" disabled={loading || pin.length !== 6 || (step === 'enroll' && confirmPIN.length !== 6)}>
                {loading ? 'Please wait…' : step === 'enroll' ? 'Save PIN' : 'Verify PIN'}
              </Button>
              <Button type="button" variant="outline" className="h-12 w-full" disabled={loading} onClick={() => {
                setError('')
                setPIN('')
                if (step === 'enroll') router.replace('/dashboard')
                else setStep('phone')
              }}>{step === 'enroll' ? 'Skip for now' : 'Use OTP instead'}</Button>
              {step === 'enroll' && <Button type="button" variant="outline" className="h-12 w-full text-rose-700" disabled={loading} onClick={() => void removePIN()}>
                Remove browser PIN
              </Button>}
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
              {error && <p role="alert" className="rounded-xl border border-rose-100 bg-rose-50 px-3.5 py-3 text-sm text-rose-700">{error}</p>}
              <Button type="submit" className="h-12 w-full rounded-xl bg-[#087F0D] text-base font-semibold hover:bg-[#06680A]" disabled={loading || otp.length !== 6}>
                {loading ? 'Verifying…' : <>Verify and continue <ArrowRight className="ml-2 h-4 w-4" /></>}
              </Button>
              <button type="button" disabled={loading || resendSeconds > 0} onClick={() => requestOtp(phone)} className="min-h-11 w-full text-sm font-medium text-[#087F0D] disabled:text-[#98A2B3]">
                {resendSeconds > 0 ? `Resend code in 00:${String(resendSeconds).padStart(2, '0')}` : 'Resend code'}
              </button>
              <button type="button" onClick={() => { setStep('phone'); setOtp(''); setError('') }} className="flex min-h-11 w-full items-center justify-center gap-2 text-sm font-medium text-[#667085] hover:text-[#087F0D]"><ArrowLeft className="h-4 w-4" /> Change mobile number</button>
            </form>
          )}
          <p className="mt-5 text-center text-xs leading-5 text-[#98A2B3]">Administrator privileges are verified after signing in. Access is protected by expiring, rotating sessions.</p>
        </CardContent>
        <CardFooter className="justify-center border-t border-[#F2F4F7] px-8 py-4">
          <Link href="/" className="text-sm font-medium text-[#667085] hover:text-[#087F0D]">Back to portal</Link>
        </CardFooter>
      </Card>
    </main>
  )
}
