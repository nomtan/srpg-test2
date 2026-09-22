// Phase 9: place a grip-attached asset (weapon / shield) on its character socket.
//
// Until now the asset root was simply parented to the socket node, so whatever the author happened
// to use as the model origin ended up at the hand. The spec has always said the asset declares an
// attachment point (`grip_main` / `grip_sub`), so that node is what must land on the socket.
//
// Shields are the case where the origin is least reliable: the demo shield's geometry sits 0.55 m
// above its origin, which hung the whole shield over the arm. When a shield has no grip node the
// bounding-box centre is used instead, which is also where a real shield meets the forearm.
import * as THREE from "three";
import type { AssetType } from "@/domain/asset-spec";
import { GRIP_ORIENTATION_DEGREES } from "@/domain/base-rig";

export type GripFallback = "center" | "origin";

export interface GripAlignment {
  /** Standard weapon orientation at the socket, in Blockbench ZYX degrees. */
  rotationDeg: readonly [number, number, number];
  /** Node that must sit on the socket; null keeps the asset origin. */
  attachmentNode: string | null;
  /** Used when `attachmentNode` is missing from the model. */
  fallback: GripFallback;
}

export type GripSlot = "main_hand" | "off_hand";

/** Place an asset that attaches at its own origin (hair, armor, ...) on the calibrated socket. */
export function applySocketOffset(root: THREE.Object3D, socketOffset: readonly number[] = [0, 0, 0]): void {
  root.position.set(socketOffset[0] ?? 0, socketOffset[1] ?? 0, socketOffset[2] ?? 0);
  root.updateMatrixWorld(true);
}

/** Null for types that attach rigidly at their origin (hair, armor, …). */
export function gripAlignmentFor(
  type: AssetType,
  slot: GripSlot = type === "shield" ? "off_hand" : "main_hand",
  attachmentNode: string | null = "grip_main",
): GripAlignment | null {
  if (type !== "weapon" && type !== "shield") return null;
  return {
    rotationDeg: GRIP_ORIENTATION_DEGREES[slot],
    attachmentNode,
    // A weapon without a grip node keeps its origin (and is reported); a shield gets centred.
    fallback: type === "shield" ? "center" : "origin",
  };
}

export interface GripAlignmentResult {
  /** How the asset was placed, for reporting. */
  placedBy: "node" | "center" | "origin";
  /** The local-space point that was moved onto the socket. */
  anchor: [number, number, number];
}

/**
 * Orients and offsets `root` so its attachment point coincides with the socket.
 * Call while `root` is still detached: the anchor is measured in the asset's own local space.
 *
 * `socketOffset` is the socket's calibrated position inside the parent node (metres). It is added
 * on top, so the asset lands on the attachment point rather than on the parent's rotation pivot.
 */
export function applyGripAlignment(
  root: THREE.Object3D,
  alignment: GripAlignment,
  socketOffset: readonly number[] = [0, 0, 0],
): GripAlignmentResult {
  root.position.set(0, 0, 0);
  root.rotation.set(0, 0, 0);
  root.updateMatrixWorld(true);

  let placedBy: GripAlignmentResult["placedBy"] = "origin";
  const anchor = new THREE.Vector3();

  const node = alignment.attachmentNode ? root.getObjectByName(alignment.attachmentNode) : null;
  if (node) {
    node.getWorldPosition(anchor);
    placedBy = "node";
  } else if (alignment.fallback === "center") {
    const box = new THREE.Box3().setFromObject(root);
    if (!box.isEmpty()) {
      box.getCenter(anchor);
      placedBy = "center";
    }
  }

  root.rotation.set(
    THREE.MathUtils.degToRad(alignment.rotationDeg[0]),
    THREE.MathUtils.degToRad(alignment.rotationDeg[1]),
    THREE.MathUtils.degToRad(alignment.rotationDeg[2]),
    "ZYX",
  );
  // The anchor is in the asset's local frame; rotate it into the socket frame before cancelling it,
  // then shift the whole asset to the socket's calibrated position inside the parent node.
  root.position
    .copy(anchor.clone().applyQuaternion(root.quaternion).negate())
    .add(new THREE.Vector3(socketOffset[0] ?? 0, socketOffset[1] ?? 0, socketOffset[2] ?? 0));
  root.updateMatrixWorld(true);

  return { placedBy, anchor: [anchor.x, anchor.y, anchor.z] };
}
