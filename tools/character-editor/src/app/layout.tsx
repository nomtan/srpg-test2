import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = { title: "Character Workshop | SRPG", description: "SRPG character asset creation tools" };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ja"><body><header className="app-header"><Link href="/" className="brand"><span aria-hidden="true">◈</span> CHARACTER WORKSHOP <small>SRPG</small></Link><nav aria-label="メインナビゲーション"><Link href="/">Character Builder</Link><Link href="/creator">Asset Creator</Link></nav><span className="local-label">LOCAL TOOL</span></header><main>{children}</main><footer>Character Asset Tool v0.1 <span>Source: Blockbench · Runtime: GLB · Y Up</span></footer></body></html>;
}
