// "use client";

// import React, { useState } from "react";
// import Image from "next/image";
// import Link from "next/link";
// import { usePathname } from "next/navigation";
// import { useAuth } from "@/context/AuthContext";

// interface MenuItem {
//   id: string;
//   label: string;
//   icon: React.ReactNode;
//   href: string;
// }

// const Sidebar: React.FC = () => {
//   const pathname = usePathname();
//   const { logout, user } = useAuth();
//   const [mobileOpen, setMobileOpen] = useState(false);

//   const handleLogout = () => {
//     logout();
//   };

//   const menuItems: MenuItem[] = [
//     {
//       id: "dashboard",
//       label: "Dashboard",
//       icon: (
//         <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
//           <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
//         </svg>
//       ),
//       href: "/dashboard",
//     },
//     {
//       id: "sales",
//       label: "Sales",
//       icon: (
//         <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
//           <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
//         </svg>
//       ),
//       href: "/sales",
//     },
//     {
//       id: "interactions",
//       label: "Interactions",
//       icon: (
//         <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
//           <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
//         </svg>
//       ),
//       href: "/interactions",
//     },
//     {
//       id: "employees",
//       label: "Employees",
//       icon: (
//         <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
//           <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
//         </svg>
//       ),
//       href: "/employees",
//     },
//     {
//       id: "info-portal",
//       label: "Info Portal",
//       icon: (
//         <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
//           <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
//         </svg>
//       ),
//       href: "/info-portal",
//     },
//   ];

//   const filteredItems = menuItems.filter((item) => {
//     if (item.id === "employees" && user?.role !== "ADMIN") return false;
//     return true;
//   });

//   const NavLinks = ({ onClickLink }: { onClickLink?: () => void }) => (
//     <ul className="space-y-1">
//       {filteredItems.map((item) => {
//         const isActive = pathname === item.href;
//         return (
//           <li key={item.id}>
//             <Link
//               href={item.href}
//               onClick={onClickLink}
//               className={`flex items-center gap-3 px-4 py-3 rounded-lg transition-colors fill-white ${
//                 isActive
//                   ? "bg-[#00337C]/11 text-[#00337C]"
//                   : "text-[#7D8592] hover:bg-gray-100"
//               }`}
//             >
//               {item.icon}
//               <span className="font-medium">{item.label}</span>
//             </Link>
//           </li>
//         );
//       })}
//     </ul>
//   );

//   return (
//     <>
//       {/* ── MOBILE TOPBAR ── */}
//       <header className="md:hidden fixed top-0 left-0 right-0 z-40 bg-white border-b border-gray-200 flex items-center justify-between px-4 py-3">
//         <Image src="/logo.svg" alt="Growmont Logo" width={120} height={32} />
//         <button
//           onClick={() => setMobileOpen((prev) => !prev)}
//           className="p-2 rounded-lg text-gray-600 hover:bg-gray-100 transition-colors"
//           aria-label="Toggle menu"
//         >
//           {mobileOpen ? (
//             /* X icon */
//             <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
//               <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
//             </svg>
//           ) : (
//             /* Hamburger icon */
//             <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
//               <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
//             </svg>
//           )}
//         </button>
//       </header>

//       {/* ── MOBILE DRAWER ── */}
//       {mobileOpen && (
//         <div className="md:hidden fixed inset-0 z-30 flex">
//           {/* Backdrop */}
//           <div
//             className="fixed inset-0 bg-black/40"
//             onClick={() => setMobileOpen(false)}
//           />
//           {/* Drawer panel */}
//           <div className="relative z-40 w-64 bg-white h-full flex flex-col shadow-xl pt-[60px]">
//             <nav className="flex-1 p-4 overflow-y-auto">
//               <NavLinks onClickLink={() => setMobileOpen(false)} />
//             </nav>
//             <div className="p-4 border-t border-gray-200">
//               <button
//                 onClick={() => { handleLogout(); setMobileOpen(false); }}
//                 className="flex items-center gap-3 px-4 py-3 text-gray-600 hover:bg-gray-100 rounded-lg w-full transition-colors"
//               >
//                 <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
//                   <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
//                 </svg>
//                 <span className="font-medium">Logout</span>
//               </button>
//             </div>
//           </div>
//         </div>
//       )}

//       {/* ── DESKTOP SIDEBAR ── */}
//       <aside className="hidden md:flex fixed left-0 top-0 h-screen w-64 bg-white border-r border-gray-200 flex-col">
//         <div className="border-b border-gray-200 flex justify-center py-5">
//           <Image src="/logo.svg" alt="Growmont Logo" width={150} height={40} />
//         </div>

//         <nav className="flex-1 p-4">
//           <NavLinks />
//         </nav>

//         <div className="p-4 border-t border-gray-200">
//           <button
//             onClick={handleLogout}
//             className="flex items-center gap-3 px-4 py-3 text-gray-600 hover:bg-gray-100 rounded-lg w-full transition-colors"
//           >
//             <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
//               <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
//             </svg>
//             <span className="font-medium">Logout</span>
//           </button>
//         </div>
//       </aside>
//     </>
//   );
// };

// export default Sidebar;

"use client";

import React, { useState, useEffect } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "@/context/AuthContext";

interface MenuItem {
  id: string;
  label: string;
  icon: React.ReactNode;
  href: string;
}

const Sidebar: React.FC = () => {
  const pathname = usePathname();
  const router = useRouter();
  const { logout, user } = useAuth();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [userName, setUserName] = useState('User');
  const [userInitials, setUserInitials] = useState('U');

  const handleLogout = () => {
    logout();
  };

  useEffect(() => {
    const user = JSON.parse(localStorage.getItem('user') || '{}');
    if (user.name) {
      setUserName(user.name);
      const initials = user.name
        .split(' ')
        .map((n: string) => n[0])
        .join('')
        .toUpperCase()
        .slice(0, 2);
      setUserInitials(initials);
    }
  }, []);

  const menuItems: MenuItem[] = [
    {
      id: "dashboard",
      label: "Dashboard",
      icon: (
        <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
        </svg>
      ),
      href: "/dashboard",
    },
    {
      id: "sales",
      label: "Sales",
      icon: (
        <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        </svg>
      ),
      href: "/sales",
    },
    {
      id: "interactions",
      label: "Interactions",
      icon: (
        <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
        </svg>
      ),
      href: "/interactions",
    },
    {
      id: "employees",
      label: "Employees",
      icon: (
        <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
        </svg>
      ),
      href: "/employees",
    },
    {
      id: "info-portal",
      label: "Info Portal",
      icon: (
        <svg className="w-5 h-5" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
        </svg>
      ),
      href: "/info-portal",
    },
  ];

  const filteredItems = menuItems.filter((item) => {
    if (item.id === "employees" && user?.role !== "ADMIN") return false;
    return true;
  });

  const NavLinks = ({ onClickLink }: { onClickLink?: () => void }) => (
    <ul className="space-y-1">
      {filteredItems.map((item) => {
        const isActive = pathname === item.href;
        return (
          <li key={item.id}>
            <Link
              href={item.href}
              onClick={onClickLink}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg transition-colors fill-white ${
                isActive
                  ? "bg-[#00337C]/11 text-[#00337C]"
                  : "text-[#7D8592] hover:bg-gray-100"
              }`}
            >
              {item.icon}
              <span className="font-medium">{item.label}</span>
            </Link>
          </li>
        );
      })}
    </ul>
  );

  return (
    <>
      {/* ── MOBILE TOPBAR ── */}
      <header className="md:hidden fixed top-0 left-0 right-0 z-40 bg-white border-b border-gray-200 flex items-center justify-between px-4 py-3">
        <Image src="/logo.svg" alt="Growmont Logo" width={120} height={32} />
        <button
          onClick={() => setMobileOpen((prev) => !prev)}
          className="p-2 rounded-lg text-gray-600 hover:bg-gray-100 transition-colors"
          aria-label="Toggle menu"
        >
          {mobileOpen ? (
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          ) : (
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          )}
        </button>
      </header>

      {/* ── MOBILE DRAWER ── */}
      {mobileOpen && (
        <div className="md:hidden fixed inset-0 z-30 flex">
          {/* Backdrop */}
          <div
            className="fixed inset-0 bg-black/40"
            onClick={() => setMobileOpen(false)}
          />
          {/* Drawer panel */}
          <div className="relative z-40 w-64 bg-white h-full flex flex-col shadow-xl pt-[60px]">
            <nav className="flex-1 p-4 overflow-y-auto">
              <NavLinks onClickLink={() => setMobileOpen(false)} />
            </nav>

            <div className="p-4 border-t border-gray-200 space-y-1">
              {/* User Profile */}
              <button
                onClick={() => { router.push('/profile'); setMobileOpen(false); }}
                className="flex items-center gap-3 px-4 py-3 text-gray-600 hover:bg-gray-100 rounded-lg w-full transition-colors"
              >
                <div className="w-8 h-8 rounded-full bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center text-white font-semibold text-sm shrink-0">
                  {userInitials}
                </div>
                <span className="font-medium text-gray-900">{userName}</span>
              </button>

              {/* Logout */}
              <button
                onClick={() => { handleLogout(); setMobileOpen(false); }}
                className="flex items-center gap-3 px-4 py-3 text-gray-600 hover:bg-gray-100 rounded-lg w-full transition-colors"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
                <span className="font-medium">Logout</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── DESKTOP SIDEBAR ── */}
      <aside className="hidden md:flex fixed left-0 top-0 h-screen w-64 bg-white border-r border-gray-200 flex-col">
        <div className="border-b border-gray-200 flex justify-center py-5">
          <Image src="/logo.svg" alt="Growmont Logo" width={150} height={40} />
        </div>

        <nav className="flex-1 p-4">
          <NavLinks />
        </nav>

        <div className="p-4 border-t border-gray-200">
          <button
            onClick={handleLogout}
            className="flex items-center gap-3 px-4 py-3 text-gray-600 hover:bg-gray-100 rounded-lg w-full transition-colors"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
            </svg>
            <span className="font-medium">Logout</span>
          </button>
        </div>
      </aside>
    </>
  );
};

export default Sidebar;