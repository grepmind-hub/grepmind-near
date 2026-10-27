'use client'

import * as React from 'react'
import { cn } from './cn'
import { ChevronRight } from 'lucide-react'

export interface SidebarProps {
  children: React.ReactNode
}
export function Sidebar({ children }: SidebarProps) {
  return (
    <aside className="fixed left-0 top-0 h-full w-64 border-r border-border bg-card text-card-foreground">
      <div className="p-6">{children}</div>
    </aside>
  )
}

export interface SidebarTriggerProps {
  children: React.ReactNode
}
export function SidebarTrigger({ children }: SidebarTriggerProps) {
  return <div className="flex items-center gap-2 px-6 py-4">{children}</div>
}

export interface SidebarContentProps {
  children: React.ReactNode
}
export function SidebarContent({ children }: SidebarContentProps) {
  return <nav className="space-y-1 px-3">{children}</nav>
}

export interface SidebarGroupProps {
  label: string
  children: React.ReactNode
}
export function SidebarGroup({ label, children }: SidebarGroupProps) {
  return (
    <div className="px-3 space-y-2 py-2">
      <h2 className="px-2 text-xs font-semibold text-muted-foreground uppercase tracking-wider">
        {label}
      </h2>
      <div className="space-y-1">{children}</div>
    </div>
  )
}

export interface SidebarMenuItemProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  href?: string
  active?: boolean
}
export function SidebarMenuItem({ className, active, href, ...props }: SidebarMenuItemProps) {
  if (href) {
    return (
      <a
        href={href}
        className={cn(
          'flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors',
          active ? 'bg-primary/10 text-primary' : 'text-muted-foreground hover:bg-accent hover:text-muted',
          className,
        )}
      >
        {props.children}
      </a>
    )
  }
  return (
    <button
      className={cn(
        'flex items-center gap-3 w-full justify-start rounded-md px-3 py-2 text-sm font-medium transition-colors',
        active ? 'bg-primary/10 text-primary' : 'text-muted-foreground hover:bg-accent hover:text-muted',
        className,
      )}
      {...props}
    />
  )
}

export interface SidebarMenuButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  active?: boolean
}
export function SidebarMenuButton({ className, active, ...props }: SidebarMenuButtonProps) {
  return (
    <button
      className={cn(
        'flex items-center gap-3 w-full justify-start rounded-md px-3 py-2 text-sm font-medium transition-colors',
        active
          ? 'bg-primary/10 text-primary'
          : 'text-muted-foreground hover:bg-accent hover:text-muted',
        className,
      )}
      {...props}
    />
  )
}

export interface SidebarLogoProps {
  children: React.ReactNode
}
export function SidebarLogo({ children }: SidebarLogoProps) {
  return <div className="flex items-center gap-2 px-6 py-4">{children}</div>
}
