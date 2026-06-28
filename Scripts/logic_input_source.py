#!/usr/bin/env python3
from __future__ import annotations

import ctypes
import ctypes.util
from typing import Final


CFSTRING_ENCODING_UTF8: Final = 0x08000100
TARGET_INPUT_SOURCE_IDS: Final[tuple[str, str]] = (
    "com.apple.keylayout.ABC",
    "com.apple.keylayout.US",
)


class TISRuntime:
    def __init__(self, carbon: ctypes.CDLL, core_foundation: ctypes.CDLL, input_source_id_key: int) -> None:
        self.carbon = carbon
        self.core_foundation = core_foundation
        self.input_source_id_key = input_source_id_key

    @classmethod
    def load(cls) -> TISRuntime | None:
        carbon_path = ctypes.util.find_library("Carbon")
        core_foundation_path = ctypes.util.find_library("CoreFoundation")
        if carbon_path is None or core_foundation_path is None:
            return None
        try:
            carbon = ctypes.CDLL(carbon_path)
            core_foundation = ctypes.CDLL(core_foundation_path)
            input_source_id_key = ctypes.c_void_p.in_dll(carbon, "kTISPropertyInputSourceID").value
        except (AttributeError, OSError, ValueError):
            return None
        if input_source_id_key is None:
            return None

        carbon.TISCreateInputSourceList.argtypes = [ctypes.c_void_p, ctypes.c_bool]
        carbon.TISCreateInputSourceList.restype = ctypes.c_void_p
        carbon.TISGetInputSourceProperty.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        carbon.TISGetInputSourceProperty.restype = ctypes.c_void_p
        carbon.TISSelectInputSource.argtypes = [ctypes.c_void_p]
        carbon.TISSelectInputSource.restype = ctypes.c_int32

        core_foundation.CFArrayGetCount.argtypes = [ctypes.c_void_p]
        core_foundation.CFArrayGetCount.restype = ctypes.c_long
        core_foundation.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
        core_foundation.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
        core_foundation.CFRelease.argtypes = [ctypes.c_void_p]
        core_foundation.CFRelease.restype = None
        core_foundation.CFStringGetLength.argtypes = [ctypes.c_void_p]
        core_foundation.CFStringGetLength.restype = ctypes.c_long
        core_foundation.CFStringGetMaximumSizeForEncoding.argtypes = [ctypes.c_long, ctypes.c_uint32]
        core_foundation.CFStringGetMaximumSizeForEncoding.restype = ctypes.c_long
        core_foundation.CFStringGetCString.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_long,
            ctypes.c_uint32,
        ]
        core_foundation.CFStringGetCString.restype = ctypes.c_bool

        return cls(carbon, core_foundation, input_source_id_key)

    def _input_sources(self) -> tuple[int, list[int]] | None:
        array_ref = int(self.carbon.TISCreateInputSourceList(None, False) or 0)
        if array_ref == 0:
            return None
        count = int(self.core_foundation.CFArrayGetCount(array_ref))
        return array_ref, [
            int(source)
            for index in range(count)
            if (source := self.core_foundation.CFArrayGetValueAtIndex(array_ref, index))
        ]

    def source_id(self, source: int) -> str | None:
        value_ref = self.carbon.TISGetInputSourceProperty(source, self.input_source_id_key)
        if not value_ref:
            return None
        length = int(self.core_foundation.CFStringGetLength(value_ref))
        buffer_size = int(
            self.core_foundation.CFStringGetMaximumSizeForEncoding(length, CFSTRING_ENCODING_UTF8)
        ) + 1
        buffer = ctypes.create_string_buffer(buffer_size)
        ok = self.core_foundation.CFStringGetCString(
            value_ref,
            buffer,
            buffer_size,
            CFSTRING_ENCODING_UTF8,
        )
        if not ok:
            return None
        return buffer.value.decode("utf-8")

    def select(self, source: int) -> bool:
        return self.carbon.TISSelectInputSource(source) == 0

    def available_source_ids(self) -> list[str] | None:
        source_set = self._input_sources()
        if source_set is None:
            return None
        array_ref, sources = source_set
        try:
            return [source_id for source in sources if (source_id := self.source_id(source)) is not None]
        finally:
            self.core_foundation.CFRelease(array_ref)

    def select_source_id(self, target_id: str) -> bool:
        source_set = self._input_sources()
        if source_set is None:
            return False
        array_ref, sources = source_set
        try:
            for source in sources:
                if self.source_id(source) == target_id:
                    return self.select(source)
            return False
        finally:
            self.core_foundation.CFRelease(array_ref)


def select_input_source(
    runtime: TISRuntime,
    target_ids: tuple[str, ...] = TARGET_INPUT_SOURCE_IDS,
) -> bool:
    source_ids = runtime.available_source_ids()
    if not source_ids:
        return False
    for target_id in target_ids:
        if target_id in source_ids and runtime.select_source_id(target_id):
            return True
    return False


def set_input_abc(runtime: TISRuntime | None = None) -> bool:
    active_runtime = runtime or TISRuntime.load()
    if active_runtime is None:
        return False
    return select_input_source(active_runtime)
