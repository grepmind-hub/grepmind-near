'use client'

import * as React from 'react'
import { cn } from './cn'

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {}

export function Input({ className, type, ...props }: InputProps) {
  return (
    <input
      type={type}
      className={cn(
        'flex h-10 w-full rounded-md border border-[#E4E7EC] bg-[#FFFFFF] px-3 py-2 text-sm placeholder:text-[#9AA5B1] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#2457D6] disabled:cursor-not-allowed disabled:opacity-50',
        className,
      )}
      {...props}
    />
  )
}
