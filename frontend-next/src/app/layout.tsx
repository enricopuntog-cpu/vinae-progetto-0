import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "./providers";
import { VineaLayout } from "@/components/vinea/Layout";

export const metadata: Metadata = {
  title: "Vinea Wine Club",
  description: "Vinea è una web app italiana per catalogare una cantina personale.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="it" className="h-full antialiased">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@500;600;700&family=Inter:wght@400;500;600;700&display=swap"
        />
      </head>
      <body className="min-h-full flex flex-col">
        <Providers>
          <VineaLayout>{children}</VineaLayout>
        </Providers>
      </body>
    </html>
  );
}
