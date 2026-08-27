# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "parakeet-mlx",
#   "fastapi",
#   "uvicorn",
#   "python-multipart",
# ]
# ///
# OpenAI-compatible speech-to-text server wrapping parakeet-mlx.
# POST /v1/audio/transcriptions (multipart: file, response_format) mirrors
# the OpenAI audio API so any OpenAI SDK works against it.
import asyncio
import os
import tempfile
from concurrent.futures import ThreadPoolExecutor

import uvicorn
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.responses import PlainTextResponse
from parakeet_mlx import from_pretrained

MODEL_ID = os.environ.get("PARAKEET_MODEL", "mlx-community/parakeet-tdt-0.6b-v3")

# MLX streams are bound to the thread they were created on, so the model must
# load and infer on the same single thread; max_workers=1 also serializes requests
mlx_thread = ThreadPoolExecutor(max_workers=1)
asr = mlx_thread.submit(from_pretrained, MODEL_ID).result()
app = FastAPI(title="parakeet-mlx")


def fmt_ts(seconds: float, sep: str) -> str:
    ms = int(round(seconds * 1000))
    h, rest = divmod(ms, 3_600_000)
    m, rest = divmod(rest, 60_000)
    s, ms = divmod(rest, 1000)
    return f"{h:02d}:{m:02d}:{s:02d}{sep}{ms:03d}"


def to_srt(sentences) -> str:
    blocks = [
        f"{i}\n{fmt_ts(s.start, ',')} --> {fmt_ts(s.end, ',')}\n{s.text.strip()}\n"
        for i, s in enumerate(sentences, 1)
    ]
    return "\n".join(blocks)


def to_vtt(sentences) -> str:
    blocks = [
        f"{fmt_ts(s.start, '.')} --> {fmt_ts(s.end, '.')}\n{s.text.strip()}\n"
        for s in sentences
    ]
    return "WEBVTT\n\n" + "\n".join(blocks)


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_ID}


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": MODEL_ID, "object": "model", "owned_by": "local"}]}


@app.post("/v1/audio/transcriptions")
async def transcriptions(
    file: UploadFile = File(...),
    response_format: str = Form("json"),
    model: str = Form(""),  # accepted for OpenAI compatibility, single-model server
):
    suffix = os.path.splitext(file.filename or "")[1] or ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        path = tmp.name
    try:
        loop = asyncio.get_running_loop()
        result = await loop.run_in_executor(mlx_thread, asr.transcribe, path)
    finally:
        os.unlink(path)

    if response_format == "text":
        return PlainTextResponse(result.text)
    if response_format == "srt":
        return PlainTextResponse(to_srt(result.sentences))
    if response_format == "vtt":
        return PlainTextResponse(to_vtt(result.sentences))
    if response_format == "verbose_json":
        return {
            "task": "transcribe",
            "duration": result.sentences[-1].end if result.sentences else 0.0,
            "text": result.text,
            "segments": [
                {"id": i, "start": s.start, "end": s.end, "text": s.text}
                for i, s in enumerate(result.sentences)
            ],
        }
    return {"text": result.text}


if __name__ == "__main__":
    uvicorn.run(
        app,
        host=os.environ.get("PARAKEET_HOST", "127.0.0.1"),
        port=int(os.environ.get("PARAKEET_PORT", "9330")),
    )
