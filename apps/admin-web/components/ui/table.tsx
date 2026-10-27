'use client'

import * as React from 'react'
import { cn } from './cn'

export interface TableProps extends React.HTMLAttributes<HTMLTableElement> {}
export function Table({ className, ...props }: TableProps) {
  return (
    <table className={'w-full text-sm caption-bottom ' + (className ?? '')} {...props} />
  )
}

export interface TableHeaderProps extends React.HTMLAttributes<HTMLTableSectionElement> {}
export function TableHeader({ className, ...props }: TableHeaderProps) {
  return <thead className={className} {...props} />
}

export interface TableBodyProps extends React.HTMLAttributes<HTMLTableSectionElement> {}
export function TableBody({ className, ...props }: TableBodyProps) {
  return <tbody className={className} {...props} />
}

export interface TableRowProps extends React.HTMLAttributes<HTMLTableRowElement> {}
export function TableRow({ className, ...props }: TableRowProps) {
  return (
    <tr
      className={cn('border-b transition-colors hover:bg-accent/50 data-[state=selected]:bg-accent', className)}
      {...props}
    />
  )
}

export interface TableHeadProps extends React.HTMLAttributes<HTMLTableCellElement> {}
export function TableHead({ className, ...props }: TableHeadProps) {
  return (
    <th
      className={cn(
        'text-left font-medium text-muted-foreground',
        className,
      )}
      {...props}
    />
  )
}

export interface TableCellProps extends React.HTMLAttributes<HTMLTableCellElement> {}
export function TableCell({ className, ...props }: TableCellProps) {
  return (
    <td className={cn('p-4 align-middle', className)} {...props} />
  )
}

export interface TableCaptionProps extends React.HTMLAttributes<HTMLTableCaptionElement> {}
export function TableCaption({ className, ...props }: TableCaptionProps) {
  return (
    <caption className={cn('mt-4 text-sm text-muted-foreground', className)} {...props} />
  )
}
