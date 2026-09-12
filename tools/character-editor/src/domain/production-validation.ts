// Phase 9 Validation Pipeline (spec section 39-41, 44).
//
// Runs against the Validation Spec that shipped with the Production Package, so the asset is
// judged by the same contract the AI agent was given. Detect-and-report only: nothing is fixed
// automatically. An error always means Fail — the score is advisory (spec section 40).
import { CHARACTER_SOCKETS, type CharacterSocket } from "./constants";
import type { GlbStats, TextureStats } from "./asset-validation";
import type { MeasuredBox } from "./base-measurements";
import { baseSocket } from "./base-measurements";
import type { ProductionIssue, ProductionValidation, ProductionVerdict } from "./production-job";
import type { ValidationSpec } from "./production-package";
import { BAKED_BASE_CLIPS, animationMapping, resolveAnimation } from "@/viewer/animation/animationMapping";

export interface ProductionInput {
  model: GlbStats | null;
  texture: TextureStats | null;
  /** `.bbmodel` source file name, when the agent returned an editable source (spec section 35). */
  sourceFileName: string | null;
}

const SCORE_PENALTY: Record<ProductionIssue["level"], number> = { error: 25, warning: 8, info: 0 };

export function scoreOf(issues: readonly ProductionIssue[]): number {
  const penalty = issues.reduce((sum, i) => sum + SCORE_PENALTY[i.level], 0);
  return Math.max(0, Math.min(100, 100 - penalty));
}

export function verdictOf(issues: readonly ProductionIssue[]): ProductionVerdict {
  if (issues.some((i) => i.level === "error")) return "fail";
  if (issues.some((i) => i.level === "warning")) return "warning";
  return "pass";
}

/** Axis-aligned overlap of two world-space boxes, as an overlap volume in m³. */
function overlapVolume(a: MeasuredBox, b: { min: number[]; max: number[] }): number {
  let volume = 1;
  for (let i = 0; i < 3; i++) {
    const span = Math.min(a.max[i], b.max[i]) - Math.max(a.min[i], b.min[i]);
    if (span <= 0) return 0;
    volume *= span;
  }
  return volume;
}

export function validateProduction(spec: ValidationSpec, input: ProductionInput): ProductionValidation {
  const issues: ProductionIssue[] = [];
  const add = (
    level: ProductionIssue["level"],
    code: string,
    check: string,
    message: string,
    detail?: Record<string, string | number>,
  ) => issues.push({ level, code, check, message, ...(detail ? { detail } : {}) });

  // ---- Model readable ----
  const model = input.model;
  if (!model) {
    add("error", "model_unreadable", "Model readable", "GLB を読み込めませんでした。Model が未 Import か、ファイルが壊れています。");
  } else if (!model.hasMesh) {
    add("error", "model_unreadable", "Model readable", "GLB に表示可能な Mesh がありません。");
  } else {
    add("info", "model_ok", "Model loaded", `Mesh ${model.meshCount} / Material ${model.materialCount} / 三角形 ${model.triangleCount.toLocaleString()}`);
  }

  // ---- Texture readable ----
  if (!input.texture) {
    add("warning", "texture_missing", "Texture readable", "Texture (PNG) が未 Import です。Palette 検証ができません。");
  } else {
    add("info", "texture_ok", "Texture loaded", `Texture ${input.texture.width} × ${input.texture.height}${input.texture.hasAlpha ? " (alpha あり)" : ""}`);
  }

  if (model?.hasMesh) {
    const size = model.boundingBox.size;
    // ---- Bounding Box ----
    if (size.some((v) => !Number.isFinite(v) || v <= 0)) {
      add("error", "bounding_box_invalid", "Bounding Box", "Bounding Box が不正です（0 または NaN の軸があります）。");
    } else {
      add("info", "bounding_box", "Bounding Box", `${size.map((v) => v.toFixed(3)).join(" × ")} m`);
    }

    // ---- Scale ----
    const longest = Math.max(...size);
    const { min, max, errorMargin } = spec.model.longestAxis;
    if (longest > max) {
      const ratio = longest / max;
      add(
        ratio > errorMargin ? "error" : "warning",
        "scale_too_large",
        "Scale",
        `Asset が想定より約 ${ratio.toFixed(2)} 倍大きいです（最長辺 ${longest.toFixed(3)} m / 上限 ${max} m）。`,
        { actual: Number(longest.toFixed(4)), expectedMax: max, ratio: Number(ratio.toFixed(2)) },
      );
    } else if (longest < min) {
      const ratio = min / longest;
      add(
        ratio > errorMargin ? "error" : "warning",
        "scale_too_small",
        "Scale",
        `Asset が想定より約 ${ratio.toFixed(2)} 倍小さいです（最長辺 ${longest.toFixed(3)} m / 下限 ${min} m）。`,
        { actual: Number(longest.toFixed(4)), expectedMin: min, ratio: Number(ratio.toFixed(2)) },
      );
    } else {
      add("info", "scale_ok", "Scale", `最長辺 ${longest.toFixed(3)} m（想定 ${min} - ${max} m）。`);
    }

    // ---- Origin / pivot ----
    const center = model.boundingBox.min.map((v, i) => v + size[i] / 2);
    const offset = Math.hypot(center[0], center[1], center[2]);
    if (offset > spec.model.maxOriginOffset) {
      add(
        "warning",
        "origin_offset",
        "Origin / Pivot",
        `Mesh 中心が原点から ${offset.toFixed(3)} m 離れています（上限 ${spec.model.maxOriginOffset} m）。取り付け位置がずれます。`,
        { offset: Number(offset.toFixed(4)), max: spec.model.maxOriginOffset },
      );
    }

    // ---- Polygon count ----
    if (model.triangleCount > spec.model.maxTriangles) {
      add(
        "warning",
        "polygon_over_budget",
        "Polygon Count",
        `Polygon 数が Budget を超えています（${model.triangleCount} > ${spec.model.maxTriangles}）。`,
        { actual: model.triangleCount, max: spec.model.maxTriangles, target: spec.model.targetTriangles },
      );
    } else {
      add("info", "polygon_ok", "Polygon Count", `${model.triangleCount} / 上限 ${spec.model.maxTriangles}`);
    }

    // ---- Material count ----
    if (model.materialCount > spec.model.maxMaterials) {
      add(
        "warning",
        "material_over_budget",
        "Material Count",
        `Material 数が多すぎます（${model.materialCount} > ${spec.model.maxMaterials}）。`,
        { actual: model.materialCount, max: spec.model.maxMaterials },
      );
    }

    // ---- UV ----
    if (spec.model.requireUv && !model.hasUv) {
      add(
        "error",
        "uv_missing",
        "UV",
        `UV を持たない Mesh が ${model.meshesWithoutUv} 個あります。Texture を適用できません。`,
        { meshesWithoutUv: model.meshesWithoutUv },
      );
    } else if (spec.model.requireUv) {
      add("info", "uv_ok", "UV", "全 Mesh に UV があります。");
    }

    // ---- Grip points ----
    for (const node of spec.model.requiredNodes) {
      const present = model.nodeNames.some((n) => n === node || n.toLowerCase() === node);
      if (present) add("info", "grip_ok", "Grip Point", `Node \`${node}\` を検出しました。`);
      else add("error", "grip_missing", "Grip Point", `Node \`${node}\` が GLB にありません。装備位置を決められません。`, { node });
    }

    // ---- Clipping (bounding box only; spec section 44) ----
    const socket = baseSocket(spec.attachment.socket as CharacterSocket);
    if (socket && spec.clearance.length) {
      const world = {
        min: model.boundingBox.min.map((v, i) => v + socket.worldPosition[i]),
        max: model.boundingBox.max.map((v, i) => v + socket.worldPosition[i]),
      };
      for (const { region, box } of spec.clearance) {
        const volume = overlapVolume(box, world);
        if (volume > 1e-4) {
          add(
            "warning",
            "possible_clipping",
            "Clipping Check",
            `Possible clipping: ${region} と約 ${(volume * 1000).toFixed(1)} L 重なっています（Bounding Box 判定）。`,
            { region, overlapVolume: Number(volume.toFixed(5)) },
          );
        }
      }
    }
  }

  // ---- Texture resolution ----
  if (input.texture) {
    const t = input.texture;
    if (spec.texture.requireSquare && t.width !== t.height) {
      add("warning", "texture_not_square", "Texture Resolution", `Texture が正方形ではありません（${t.width} × ${t.height}）。`);
    }
    if (t.width !== spec.texture.width || t.height !== spec.texture.height) {
      add(
        "error",
        "texture_wrong_size",
        "Texture Resolution",
        `Texture 解像度が仕様と異なります（${t.width} × ${t.height} / 仕様 ${spec.texture.width} × ${spec.texture.height}）。`,
        { actualWidth: t.width, actualHeight: t.height, expectedWidth: spec.texture.width, expectedHeight: spec.texture.height },
      );
    } else {
      add("info", "texture_size_ok", "Texture Resolution", `${t.width} × ${t.height}`);
    }

    // ---- Transparency policy ----
    if (spec.texture.alphaPolicy === "alpha_forbidden" && t.hasAlpha) {
      add("warning", "alpha_not_allowed", "Transparency", "この Asset Type では alpha は禁止ですが、Texture に透過があります。");
    } else if (spec.texture.alphaPolicy === "alpha_required" && !t.hasAlpha) {
      add("warning", "alpha_required", "Transparency", "この Asset Type は alpha が必要ですが、Texture が完全不透明です。");
    }
  }

  // ---- Palette slots ----
  if (!spec.palette.slots.length) {
    add("warning", "palette_missing", "Palette Slots", "Palette Slot が宣言されていません。Palette Swap ができません。");
  } else if (spec.assetType === "hair" && !spec.palette.slots.includes("hair")) {
    add("error", "palette_slot_missing", "Palette Slots", "Hair Asset に palette slot `hair` がありません。Hair 色のバリエーションが作れません。", { slot: "hair" });
  } else {
    add("info", "palette_ok", "Palette Slots", spec.palette.slots.join(", "));
  }

  // ---- Socket ----
  if (!CHARACTER_SOCKETS.includes(spec.attachment.socket as CharacterSocket)) {
    add("error", "socket_unknown", "Socket", `未定義の Socket です: ${spec.attachment.socket}`, { socket: spec.attachment.socket });
  } else {
    add("info", "socket_ok", "Socket", `${spec.attachment.socket} に対応します。`);
  }

  // ---- Body type ----
  if (!spec.bodyTypes.length) {
    add("error", "bodytype_missing", "BodyType", "Body Type が 1 つも指定されていません。");
  } else {
    add("info", "bodytype_ok", "BodyType", spec.bodyTypes.join(", "));
  }

  // ---- Animation compatibility ----
  // An animation set the base cannot play at all is the asset's problem (warning). A single role
  // the baked base happens not to provide is a known base-model gap, reported but not blocking.
  const setIsMapped = Object.values(animationMapping).some((m) => m.set === spec.animation.set);
  if (!setIsMapped) {
    add(
      "warning",
      "animation_set_unsupported",
      "Animation compatibility",
      `Animation Set \`${spec.animation.set}\` の clip が base_1 にありません。この Asset を装備した Character は既定 Animation へ Fallback します。`,
      { set: spec.animation.set },
    );
  } else {
    const missing: string[] = [];
    const resolved: string[] = [];
    for (const role of spec.animation.roles) {
      const hit = resolveAnimation(spec.animation.set, role, BAKED_BASE_CLIPS);
      if (hit.name) resolved.push(`${role} → ${hit.name}`);
      else missing.push(`${spec.animation.set}.${role}`);
    }
    if (resolved.length) {
      add("info", "animation_ok", "Animation compatibility", `Animation Test: ${resolved.join(" · ")}`);
    }
    if (missing.length) {
      add(
        "info",
        "animation_clip_absent",
        "Animation compatibility",
        `base_1 に該当 clip がない Animation Test: ${missing.join(" · ")}（Base 側の制約。Asset の修正対象ではありません）`,
      );
    }
  }

  // ---- Editable source ----
  if (!input.sourceFileName) {
    add("info", "source_missing", "Source", "`.bbmodel` Source が未添付です（任意ですが、後の修正が楽になります）。");
  } else {
    add("info", "source_ok", "Source", `Source: ${input.sourceFileName}`);
  }

  return {
    verdict: verdictOf(issues),
    score: scoreOf(issues),
    checkedAt: new Date().toISOString(),
    issues,
  };
}

export const countIssues = (issues: readonly ProductionIssue[]) => ({
  error: issues.filter((i) => i.level === "error").length,
  warning: issues.filter((i) => i.level === "warning").length,
  info: issues.filter((i) => i.level === "info").length,
});
