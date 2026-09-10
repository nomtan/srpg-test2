import analysis from "../../../public/generated-assets/base_body/analysis.json";
import comparison from "../../../public/generated-assets/base_body/comparison.json";

/** Server-rendered summary; the browser preview only loads GLB, never bbmodel. */
export function BaseModelSummary() {
  return <section className="panel base-analysis">
    <div className="panel-heading"><h2>基準素体の解析</h2><span className="badge">SOURCE OF TRUTH</span></div>
    <div className="analysis-content">
      <p><code>{analysis.source.path}</code></p>
      <p>{analysis.counts.groups} Groups · {analysis.counts.bodyParts} Body Parts（表示 {analysis.counts.previewMeshes}）· {analysis.counts.animations} Animations · Texture画像なし</p>
      <p>Source: {analysis.bounds.size.map((n) => n.toFixed(4)).join(" × ")} BB units ／ Runtime: {analysis.bounds.size.map((n) => (n * analysis.coordinates.metersPerSourceUnit).toFixed(4)).join(" × ")} m（X / Y / Z）</p>
      <p>+X 前方 / +Y 上 / +Z 左。Explorerと同じ1/12スケール。元ファイル・既存Group・Rest Poseの傾きは変更していません。</p>
      <p className="parity-notice">{comparison.parityGate.numericParity ? "Explorerの静止形状・Scale・向きは数値比較で一致しました。" : "Explorerとの数値比較に差があります。"} 実画面での目視確認は未完了です。色は中立Materialで表示し、Animation再生・Asset装着には進みません。</p>
      <details><summary>Body Part一覧（UUIDで識別）</summary><div className="table-scroll"><table><thead><tr><th>元の名称</th><th>表示</th><th>UUID</th></tr></thead><tbody>{analysis.bodyParts.map((p) => <tr key={p.uuid}><td>{p.name}</td><td>{p.visible ? "表示" : "非表示"}</td><td><code>{p.uuid}</code></td></tr>)}</tbody></table></div></details>
      <details><summary>Existing Group → Standard Role</summary><div className="table-scroll"><table><thead><tr><th>Group</th><th>Role</th><th>Pivot（BB）</th></tr></thead><tbody>{analysis.groups.filter((g) => g.role).map((g) => <tr key={g.uuid}><td>{g.name}</td><td>{g.role}</td><td>{g.origin.join(", ")}</td></tr>)}</tbody></table></div></details>
      <details><summary>既存Animation一覧（解析のみ）</summary><ul>{analysis.animations.map((a) => <li key={a.uuid}>{a.name} · {a.length}s · {a.loop} · {a.keyframeCount} keys</li>)}</ul></details>
      <details><summary>Equipment分類・Socket</summary><p>onehand_sword / spear / gread_sword / dagger_left / allow は左手側、bow / dagger_right / shield は右側の既存階層です。綴りも左右も変更しません。</p><p>Socketはアプリ側定義のみ。既存Pivotを仮の基点とし、取り付け位置の調整・検証は未実施です。</p></details>
      <p><a href="/generated-assets/base_body/analysis.json" download>解析JSON</a> · <a href="/generated-assets/base_body/asset.json" download>Asset Metadata</a> · <a href="/generated-assets/base_body/model.glb" download>生成GLB</a> · <a href="/generated-assets/base_body/comparison.json" download>数値比較結果</a></p>
    </div>
  </section>;
}
