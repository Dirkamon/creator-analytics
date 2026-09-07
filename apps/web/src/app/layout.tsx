import "./globals.css";
import type { Metadata, Viewport } from "next";
import { themeInitializationScript } from "@/lib/theme";

export const metadata: Metadata = {
  title: {
    default: "Creator Analytics",
    template: "%s · Creator Analytics",
  },
  description:
    "Your private workspace for content, performance, and scheduling.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  colorScheme: "dark light",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" data-theme="midnight" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{ __html: themeInitializationScript }}
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
