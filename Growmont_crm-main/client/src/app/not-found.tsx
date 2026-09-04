"use client";

import Link from "next/link";
import Image from "next/image";

export default function NotFound() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-green-50 via-white to-emerald-50 flex items-center justify-center px-4 py-10">
      <div className="w-full max-w-2xl rounded-3xl border border-green-100 bg-white/90 shadow-[0_20px_60px_-20px_rgba(0,0,0,0.18)] backdrop-blur p-8 md:p-12 text-center">
        <div className="flex justify-center mb-6">
          <Image src="/logo.svg" alt="Growmont Logo" width={220} height={60} priority />
        </div>

        <div className="inline-flex items-center justify-center w-20 h-20 rounded-full bg-green-100 text-green-700 text-4xl font-bold mb-6">
          404
        </div>

        <h1 className="text-3xl md:text-4xl font-bold text-gray-900 mb-3">
          Page not found
        </h1>
        <p className="text-lg text-gray-600 mb-8">
          The page you are looking for does not exist or may have been moved.
        </p>

        <Link
          href="/"
          className="inline-flex items-center justify-center rounded-full bg-green-700 px-6 py-3 text-sm font-semibold text-white shadow-sm transition hover:bg-green-800"
        >
          Go back home
        </Link>
      </div>
    </div>
  );
}
