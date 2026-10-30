import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Merchant Workspace | Grepmind Near',
  description: 'Manage your local business presence, service requests, store catalog, and operating hours on Grepmind Near.',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="font-sans bg-background min-h-screen text-slateText-main antialiased">
        {children}
      </body>
    </html>
  );
}
