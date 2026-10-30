'use client';

import React from 'react';
import { History, Shield, Calendar, User } from 'lucide-react';
import { AuditLog } from '@/lib/api';

interface AuditLogsViewProps {
  logs: AuditLog[];
}

export const AuditLogsView: React.FC<AuditLogsViewProps> = ({ logs }) => {
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-bold text-[#172033]">Platform Audit Trail</h2>
        <p className="text-xs text-[#667085] mt-0.5">
          Immutable compliance record of all administrative approvals, verifications, and moderations
        </p>
      </div>

      <div className="rounded-2xl border border-[#E4E7EC] bg-white shadow-xs overflow-hidden">
        <table className="w-full text-left border-collapse text-xs">
          <thead>
            <tr className="border-b border-[#E4E7EC] bg-[#F7F8FA] text-[#667085] font-semibold">
              <th className="py-3 px-4">Timestamp</th>
              <th className="py-3 px-4">Action Taken</th>
              <th className="py-3 px-4">Target Entity</th>
              <th className="py-3 px-4">Moderator Notes</th>
              <th className="py-3 px-4">Actor</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[#F2F4F7]">
            {logs.map((log) => (
              <tr key={log.id} className="hover:bg-[#FAFAFA] transition-colors">
                <td className="py-3 px-4 text-[#667085] whitespace-nowrap">
                  {new Date(log.created_at).toLocaleString()}
                </td>
                <td className="py-3 px-4">
                  <span className="rounded-md bg-blue-50 px-2 py-0.5 font-mono text-[11px] font-bold text-[#2457D6]">
                    {log.action}
                  </span>
                </td>
                <td className="py-3 px-4 text-[#344054]">
                  <span className="capitalize font-semibold text-[#172033]">{log.target_type}</span>
                  <div className="text-[10px] text-[#98A2B3] font-mono">{log.target_id}</div>
                </td>
                <td className="py-3 px-4 text-[#475467]">
                  {log.reason || 'Verified administrative action'}
                </td>
                <td className="py-3 px-4 text-[#667085] whitespace-nowrap font-mono text-[11px]">
                  {log.actor_phone || '+91 00000 00000'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
};
