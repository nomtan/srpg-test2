"use client";

// Header navigation. Client-side only so the current route can be highlighted; the layout itself
// stays a server component.
import Link from "next/link";
import { usePathname } from "next/navigation";

const LINKS = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/characters", label: "Character Library" },
  { href: "/", label: "Character Builder" },
  { href: "/variations", label: "Variation Generator" },
  { href: "/assets", label: "Asset Library" },
  { href: "/creator", label: "Asset Creator" },
  { href: "/production", label: "AI Production" },
  { href: "/validation", label: "Validation" },
] as const;

/** Character Builder is the root, so it only matches exactly; the rest also match their subpaths. */
function isActive(href: string, pathname: string): boolean {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function MainNav() {
  const pathname = usePathname() ?? "/";
  return (
    <nav aria-label="メインナビゲーション">
      {LINKS.map(({ href, label }) => {
        const active = isActive(href, pathname);
        return (
          <Link
            key={href}
            href={href}
            className={active ? "active" : undefined}
            aria-current={active ? "page" : undefined}
          >
            {label}
          </Link>
        );
      })}
    </nav>
  );
}
