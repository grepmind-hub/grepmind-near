'use client';

import React, { useState } from 'react';
import { 
  Store, 
  ShieldCheck, 
  Phone, 
  ArrowRight, 
  KeyRound, 
  CheckCircle2, 
  AlertCircle, 
  Lock, 
  Sparkles,
  Building2,
  ChevronRight
} from 'lucide-react';
import { MerchantSession } from '../lib/types';

interface AuthLoginViewProps {
  onLoginSuccess: (session: MerchantSession, isNewUser?: boolean) => void;
}

export const AuthLoginView: React.FC<AuthLoginViewProps> = ({ onLoginSuccess }) => {
  const [phone, setPhone] = useState('+91 ');
  const [step, setStep] = useState<'phone' | 'otp'>('phone');
  const [otpDigits, setOtpDigits] = useState(['', '', '', '', '', '']);
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState('');
  const [activeAccountLabel, setActiveAccountLabel] = useState<string>('');

  const DEMO_ACCOUNTS: {label:string;phone:string;role:'owner'|'manager'|'staff';name:string;desc:string;color:string;badge:string}[] = [];

  const handleSelectDemo = (account: typeof DEMO_ACCOUNTS[0]) => {
    setPhone(account.phone);
    setActiveAccountLabel(account.label);
    setErrorMessage('');
  };

  const handleSendOtp = async (e: React.FormEvent) => {
    e.preventDefault();
    const cleanPhone = phone.trim();
    if (cleanPhone.length < 10) {
      setErrorMessage('Please enter a valid mobile number (e.g., +91 98765 43210).');
      return;
    }

    setIsLoading(true);
    setErrorMessage('');

    try {
      const response = await fetch('/api/v1/auth/otp/request', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({phone_e164:cleanPhone.replace(/\s+/g,'')}) });
      if (!response.ok) throw new Error('Unable to request a verification code.');
      setStep('otp');
      setOtpDigits(['', '', '', '', '', '']);
    } catch (_) { setErrorMessage('Unable to request a verification code.'); }
    finally {setIsLoading(false);}
  };

  const handleOtpChange = (index: number, value: string) => {
    if (value.length > 1) {
      value = value[value.length - 1];
    }
    const newDigits = [...otpDigits];
    newDigits[index] = value;
    setOtpDigits(newDigits);

    // Auto advance focus
    if (value && index < 5) {
      const nextInput = document.getElementById(`otp-${index + 1}`);
      nextInput?.focus();
    }
  };

  const handleVerifyOtp = async (e: React.FormEvent) => {
    e.preventDefault();
    const enteredCode = otpDigits.join('');
    if (enteredCode.length !== 6) {
      setErrorMessage('Please enter all 6 digits of the OTP.');
      return;
    }

    setIsLoading(true);
    setErrorMessage('');

    try {
      const cleanPhone = phone.replace(/\s+/g, '');
      const response=await fetch('/api/v1/auth/otp/verify',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({phone_e164:cleanPhone,otp_code:enteredCode})});
      if(!response.ok) throw new Error('Verification failed');
      const {data}=await response.json();
      localStorage.setItem('grepmind_merchant_token',data.access_token);
      const session: MerchantSession = {
        userId: data.user.id,
        name: data.user.display_name || 'Merchant',
        phone: cleanPhone,
        role: 'staff', // Backend ownership checks determine privileges.
        token: data.access_token,
      };
      onLoginSuccess(session);
    } catch (_) {setErrorMessage('Invalid or expired verification code.');}
    finally {setIsLoading(false);}
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 via-blue-50/30 to-slate-100 flex items-center justify-center p-4">
      <div className="w-full max-w-4xl grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">
        
        {/* Left Column: Brand & Security Isolation Guarantee */}
        <div className="lg:col-span-5 space-y-6">
          <div className="flex items-center space-x-3">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary text-white shadow-lg shadow-primary/20">
              <Store className="h-6 w-6" />
            </div>
            <div>
              <div className="flex items-center space-x-2">
                <span className="text-lg font-black tracking-tight text-slateText-main">
                  Grepmind Near
                </span>
                <span className="rounded-md bg-primary/10 px-2 py-0.5 text-[11px] font-bold text-primary">
                  Merchant
                </span>
              </div>
              <p className="text-xs text-slateText-secondary">Storefront & Trade Management</p>
            </div>
          </div>

          <div className="space-y-3">
            <h1 className="text-2xl font-black text-slateText-main tracking-tight leading-snug">
              Sign in to your Merchant Workspace
            </h1>
            <p className="text-xs text-slateText-secondary leading-relaxed">
              Manage your storefront catalog, accept live customer bookings, adjust service radius, and delegate operations to staff.
            </p>
          </div>

          {/* Merchant-Level Isolation Guarantee Card */}
          <div className="rounded-2xl border border-emerald-200 bg-emerald-50/60 p-4 shadow-sm space-y-2">
            <div className="flex items-center space-x-2 text-emerald-800">
              <ShieldCheck className="h-4 w-4 text-emerald-600" />
              <span className="text-xs font-bold">Strict Tenant Isolation Active</span>
            </div>
            <p className="text-[11px] text-emerald-900/80 leading-relaxed">
              Every merchant workspace is strictly sandboxed. You will <strong>only</strong> see customer bookings, products, inventory, and analytics belonging exclusively to your registered store.
            </p>
          </div>

          <div className="rounded-xl border border-borderMuted bg-surface p-3.5 text-xs text-slateText-secondary flex items-center space-x-3">
            <Lock className="h-4 w-4 text-slateText-muted shrink-0" />
            <span>Passwordless access secured with time-limited Phone OTP.</span>
          </div>
        </div>

        {/* Right Column: Authentication Form Card */}
        <div className="lg:col-span-7 rounded-3xl border border-borderMuted bg-surface p-7 shadow-xl">
          {errorMessage && (
            <div className="mb-5 flex items-center space-x-2.5 rounded-xl bg-rose-50 border border-rose-200 p-3.5 text-xs text-rose-700">
              <AlertCircle className="h-4 w-4 shrink-0" />
              <span>{errorMessage}</span>
            </div>
          )}

          {step === 'phone' ? (
            <div className="space-y-5">
              <div>
                <h2 className="text-base font-bold text-slateText-main">Enter Your Mobile Number</h2>
                <p className="text-xs text-slateText-secondary mt-0.5">
                  We will send a 6-digit verification code to your phone
                </p>
              </div>

              <form onSubmit={handleSendOtp} className="space-y-4">
                <div>
                  <label className="block text-xs font-bold text-slateText-main mb-1.5">
                    Mobile Number (with +91)
                  </label>
                  <div className="relative">
                    <Phone className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slateText-muted" />
                    <input
                      type="tel"
                      required
                      placeholder="+91 98765 43210"
                      value={phone}
                      onChange={(e) => setPhone(e.target.value)}
                      className="w-full rounded-xl border border-borderMuted bg-background pl-10 pr-3.5 py-3 text-sm font-semibold text-slateText-main placeholder:text-slateText-muted focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={isLoading}
                  className="w-full flex items-center justify-center space-x-2 rounded-xl bg-primary py-3 text-xs font-bold text-white hover:bg-primary/90 transition-all shadow-md shadow-primary/20 disabled:opacity-50"
                >
                  {isLoading ? (
                    <span>Sending Code...</span>
                  ) : (
                    <>
                      <span>Get Verification Code</span>
                      <ArrowRight className="h-4 w-4" />
                    </>
                  )}
                </button>
              </form>

              {/* Demo Account Quick Switcher Chips */}
              <div className="pt-4 border-t border-borderMuted space-y-2.5">
                <div className="flex items-center justify-between">
                  <span className="text-[11px] font-bold text-slateText-muted uppercase tracking-wider">
                    Quick-Fill Test Accounts:
                  </span>
                  <span className="text-[10px] text-slateText-muted">Click to select role</span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {DEMO_ACCOUNTS.map((acc) => (
                    <button
                      key={acc.phone}
                      type="button"
                      onClick={() => handleSelectDemo(acc)}
                      className={`text-left rounded-xl border p-2.5 transition-all text-xs ${acc.color} ${
                        phone === acc.phone ? 'ring-2 ring-primary shadow-sm' : ''
                      }`}
                    >
                      <div className="font-bold flex items-center justify-between">
                        <span className="truncate">{acc.name}</span>
                        <span className="text-[9px] font-mono px-1.5 py-0.5 rounded bg-white/80 border border-current">
                          {acc.badge}
                        </span>
                      </div>
                      <div className="text-[11px] opacity-80 font-mono mt-0.5">{acc.phone}</div>
                      <div className="text-[10px] opacity-70 mt-1 line-clamp-1">{acc.desc}</div>
                    </button>
                  ))}
                </div>
              </div>
            </div>
          ) : (
            <div className="space-y-5">
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="text-base font-bold text-slateText-main">Enter 6-Digit OTP</h2>
                  <p className="text-xs text-slateText-secondary mt-0.5">
                    Code sent to <strong className="text-slateText-main">{phone}</strong>
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => setStep('phone')}
                  className="text-xs font-bold text-primary hover:underline"
                >
                  Change
                </button>
              </div>

              <form onSubmit={handleVerifyOtp} className="space-y-5">
                <div className="flex justify-between gap-2">
                  {otpDigits.map((digit, idx) => (
                    <input
                      key={idx}
                      id={`otp-${idx}`}
                      type="text"
                      maxLength={1}
                      value={digit}
                      onChange={(e) => handleOtpChange(idx, e.target.value)}
                      className="h-12 w-12 rounded-xl border border-borderMuted bg-background text-center text-lg font-black text-slateText-main focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 shadow-sm"
                    />
                  ))}
                </div>

                <div className="rounded-xl bg-blue-50/70 border border-blue-200/60 p-3 text-xs text-blue-900 flex items-center justify-between">
                  <div className="flex items-center space-x-2">
                    <CheckCircle2 className="h-4 w-4 text-primary shrink-0" />
                    <span>Enter the verification code you received.</span>
                  </div>
                  <button
                    type="button"
                    onClick={() => setOtpDigits(['', '', '', '', '', ''])}
                    className="font-bold text-primary hover:underline text-[11px]"
                  >
                    Clear
                  </button>
                </div>

                <button
                  type="submit"
                  disabled={isLoading}
                  className="w-full flex items-center justify-center space-x-2 rounded-xl bg-primary py-3 text-xs font-bold text-white hover:bg-primary/90 transition-all shadow-md shadow-primary/20 disabled:opacity-50"
                >
                  {isLoading ? (
                    <span>Verifying Code...</span>
                  ) : (
                    <>
                      <span>Verify & Access Workspace</span>
                      <ChevronRight className="h-4 w-4" />
                    </>
                  )}
                </button>
              </form>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
