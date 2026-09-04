"use client";

import React, { useState } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";

interface LoginResponse {
  access: string;
  refresh: string;
  user: {
    id: number;
    name: string;
    email: string;
    avatar: string | null;
    role: 'ADMIN' | 'EMPLOYEE';
  };
}
// const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000';
const API_URL = "";

const LoginPage = () => {
  const router = useRouter();

  const [formData, setFormData] = useState({
    username: "",
    password: "",
  });

  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({
      ...prev,
      [name]: value,
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      console.log('Attempting login...');
      
      const res = await fetch(`/api/auth/login/`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          username: formData.username,
          password: formData.password,
        }),
      });

      // Check if response is JSON
      const contentType = res.headers.get('content-type');
      const isJson = contentType?.includes('application/json');

      if (!res.ok) {
        if (isJson) {
          const errorData = await res.json();
          console.error('Backend error details:', errorData);  // ← Add this
          throw new Error(errorData.detail || errorData.error || "Invalid credentials");
        } else {
          const text = await res.text();  // ← Add this to see HTML error
          console.error('Non-JSON response:', text);  // ← Add this
          throw new Error(`Server error (${res.status}). Check backend logs.`);
        }
      }


      if (!isJson) {
        throw new Error("Server returned invalid response format. Backend may not be running.");
      }

      const data: LoginResponse = await res.json();
      console.log('Login response:', data);

      // Store tokens and user data
      localStorage.setItem("accessToken", data.access);
      localStorage.setItem("refreshToken", data.refresh);
      localStorage.setItem("user", JSON.stringify(data.user));

      console.log("Login successful, redirecting to dashboard...");

      // Use window.location for a hard redirect to ensure clean state
      window.location.href = "/dashboard";
      
    } catch (err) {
      console.error("Login error:", err);
      if (err instanceof Error) {
        setError(err.message);
      } else {
        setError("An unexpected error occurred. Please try again.");
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex h-screen bg-white">
      {/* Left Side - Image */}
      <div className="hidden lg:flex lg:w-1/2 relative">
        <Image
          src="/login_bg.png"
          alt="Login Background"
          fill
          className="object-cover rounded-br-3xl rounded-tr-3xl"
          priority
        />
      </div>

      {/* Right Side - Login Form */}
      <div className="flex-1 flex items-center justify-center p-8 lg:w-1/2">
        <div className="w-full max-w-md">
          <div className="flex justify-center mb-12">
            <Image
              src="/logo.svg"
              alt="Growmont Logo"
              width={280}
              height={80}
              priority
            />
          </div>

          <div className="text-center mb-10">
            <h1 className="text-3xl font-bold text-green-700 relative inline-block">
              Login
              <span className="absolute bottom-0 left-0 w-full h-0.5 bg-green-700"></span>
            </h1>
          </div>

          {/* Error Message */}
          {error && (
            <div className="bg-red-50 border border-red-300 text-red-700 px-4 py-3 rounded-lg mb-4">
              {error}
            </div>
          )}

          {/* Login Form */}
          <form onSubmit={handleSubmit} className="space-y-6">
            <div>
              <input

                suppressHydrationWarning
                type="text"
                name="username"
                value={formData.username}
                onChange={handleChange}
                placeholder="Username / Email"
                required
                className="w-full px-6 py-4 bg-gray-100 rounded-full text-gray-700 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-green-500 transition"
              />
            </div>

            <div className="relative">
              <input
                type={showPassword ? "text" : "password"}
                name="password"
                value={formData.password}
                onChange={handleChange}
                placeholder="Password"
                required
                className="w-full px-6 py-4 bg-gray-100 rounded-full text-gray-700 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-green-500 transition pr-14"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-6 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-700 transition"
              >
                {showPassword ? (
                  <svg
                    className="w-6 h-6"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243"
                    />
                  </svg>
                ) : (
                  <svg
                    className="w-6 h-6"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                    />
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                    />
                  </svg>
                )}
              </button>
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-green-700 hover:bg-green-800 disabled:opacity-60 text-white font-semibold py-4 rounded-full transition duration-300 shadow-lg hover:shadow-xl mt-8"
            >
              {loading ? "Logging in..." : "Login"}
            </button>
          </form>

          
        </div>
      </div>
    </div>
  );
};

export default LoginPage;