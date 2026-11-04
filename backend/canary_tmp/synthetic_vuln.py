# Sintetico, VPM-018-SEC-CI-01: ramo di prova mai fuso. Valore casuale, non e' una credenziale.
import sqlite3
import subprocess
from flask import Flask, request

app = Flask(__name__)
api_key = "zChPeqmAQjDXCvPSgEh37M3OH2jKIHi7ZeDWdu2x"

@app.route("/x")
def x():
    subprocess.call(request.args["c"], shell=True)
    conn = sqlite3.connect(":memory:")
    return str(conn.execute("select * from t where a = '" + request.args["a"] + "'").fetchall())
