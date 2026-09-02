#!/bin/bash

set -e

echo "Creating ZimPlug Music..."

mkdir -p templates static/css static/js static/images static/music

# Copy the transparent logo supplied for ZimPlug Music
if [ -f "/mnt/data/a_clean_vector_style_logo_graphic_on_a_transparent.png" ]; then
    cp "/mnt/data/a_clean_vector_style_logo_graphic_on_a_transparent.png" static/images/logo.png
fi

cat > requirements.txt <<'REQ'
Flask>=3.0,<4.0
REQ

cat > app.py <<'PY'
import os
import sqlite3
from pathlib import Path
from functools import wraps
from flask import (
    Flask,
    render_template,
    request,
    redirect,
    url_for,
    jsonify,
    send_from_directory,
    session,
    abort,
)
from werkzeug.utils import secure_filename

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "zimplug.db"
MUSIC_DIR = BASE_DIR / "static" / "music"

MUSIC_DIR.mkdir(parents=True, exist_ok=True)

app = Flask(__name__)
app.secret_key = os.environ.get(
    "ZIMPLUG_SECRET",
    "zimplug-music-change-this-secret"
)

ADMIN_USERNAME = os.environ.get("ZIMPLUG_ADMIN", "admin")
ADMIN_PASSWORD = os.environ.get("ZIMPLUG_ADMIN_PASSWORD", "zimplug123")

ALLOWED_AUDIO = {
    ".mp3",
    ".wav",
    ".m4a",
    ".aac",
    ".ogg",
}

ALLOWED_IMAGE = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
}


def db():
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def init_db():
    connection = db()

    connection.execute("""
        CREATE TABLE IF NOT EXISTS songs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            genre TEXT DEFAULT 'Other',
            album TEXT DEFAULT '',
            cover TEXT DEFAULT '',
            audio TEXT NOT NULL,
            plays INTEGER DEFAULT 0,
            downloads INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    connection.execute("""
        CREATE TABLE IF NOT EXISTS news (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            image TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    connection.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    connection.commit()
    connection.close()


init_db()


def admin_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("admin"):
            return redirect(url_for("admin_login"))
        return view(*args, **kwargs)

    return wrapped


def get_trending_songs(limit=10):
    connection = db()
    songs = connection.execute("""
        SELECT *
        FROM songs
        ORDER BY plays DESC, downloads DESC, created_at DESC
        LIMIT ?
    """, (limit,)).fetchall()
    connection.close()
    return songs


def get_trending_albums(limit=10):
    connection = db()

    albums = connection.execute("""
        SELECT
            album,
            artist,
            MAX(cover) AS cover,
            SUM(plays) AS plays,
            SUM(downloads) AS downloads,
            COUNT(*) AS tracks
        FROM songs
        WHERE album IS NOT NULL
          AND album != ''
        GROUP BY album, artist
        ORDER BY plays DESC, downloads DESC
        LIMIT ?
    """, (limit,)).fetchall()

    connection.close()
    return albums


@app.route("/")
def home():
    songs = get_trending_songs(8)
    albums = get_trending_albums(6)

    return render_template(
        "index.html",
        songs=songs,
        albums=albums,
    )


@app.route("/music")
def music():
    genre = request.args.get("genre", "").strip()

    connection = db()

    if genre:
        songs = connection.execute("""
            SELECT *
            FROM songs
            WHERE LOWER(genre) = LOWER(?)
            ORDER BY plays DESC, created_at DESC
        """, (genre,)).fetchall()
    else:
        songs = connection.execute("""
            SELECT *
            FROM songs
            ORDER BY created_at DESC
        """).fetchall()

    connection.close()

    genres = [
        "AfroSounds",
        "Afrobeats",
        "Hip Hop",
        "Zimdancehall",
        "R&B",
        "Amapiano",
        "Gospel",
        "Dance",
        "Pop",
        "Soul",
        "Reggae",
        "Other",
    ]

    return render_template(
        "music.html",
        songs=songs,
        genres=genres,
        selected_genre=genre,
    )


@app.route("/news")
def news():
    connection = db()
    articles = connection.execute("""
        SELECT *
        FROM news
        ORDER BY created_at DESC
    """).fetchall()
    connection.close()

    return render_template(
        "news.html",
        articles=articles,
    )


@app.route("/register", methods=["GET", "POST"])
def register():
    message = ""

    if request.method == "POST":
        name = request.form.get("name", "").strip()
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")

        if not name or not email or not password:
            message = "Please complete all fields."
        else:
            connection = db()

            try:
                connection.execute("""
                    INSERT INTO users(name, email, password)
                    VALUES (?, ?, ?)
                """, (name, email, password))

                connection.commit()
                connection.close()

                return redirect(url_for("home"))

            except sqlite3.IntegrityError:
                connection.close()
                message = "An account with that email already exists."

    return render_template(
        "register.html",
        message=message,
    )


@app.route("/play/<int:song_id>", methods=["POST"])
def play(song_id):
    connection = db()

    song = connection.execute(
        "SELECT * FROM songs WHERE id = ?",
        (song_id,)
    ).fetchone()

    if not song:
        connection.close()
        return jsonify({"error": "Song not found"}), 404

    connection.execute("""
        UPDATE songs
        SET plays = plays + 1
        WHERE id = ?
    """, (song_id,))

    connection.commit()

    updated = connection.execute(
        "SELECT plays FROM songs WHERE id = ?",
        (song_id,)
    ).fetchone()

    connection.close()

    return jsonify({
        "success": True,
        "plays": updated["plays"],
    })


@app.route("/download/<int:song_id>")
def download(song_id):
    connection = db()

    song = connection.execute(
        "SELECT * FROM songs WHERE id = ?",
        (song_id,)
    ).fetchone()

    if not song:
        connection.close()
        abort(404)

    connection.execute("""
        UPDATE songs
        SET downloads = downloads + 1
        WHERE id = ?
    """, (song_id,))

    connection.commit()
    connection.close()

    filename = Path(song["audio"]).name

    return send_from_directory(
        MUSIC_DIR,
        filename,
        as_attachment=True,
        download_name=filename,
    )


@app.route("/admin/login", methods=["GET", "POST"])
def admin_login():
    error = ""

    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")

        if username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
            session["admin"] = True
            return redirect(url_for("admin"))

        error = "Invalid admin login."

    return render_template(
        "admin_login.html",
        error=error,
    )


@app.route("/admin/logout")
def admin_logout():
    session.pop("admin", None)
    return redirect(url_for("home"))


@app.route("/admin")
@admin_required
def admin():
    connection = db()

    songs = connection.execute("""
        SELECT *
        FROM songs
        ORDER BY created_at DESC
    """).fetchall()

    articles = connection.execute("""
        SELECT *
        FROM news
        ORDER BY created_at DESC
    """).fetchall()

    connection.close()

    return render_template(
        "admin.html",
        songs=songs,
        articles=articles,
    )


@app.route("/admin/upload", methods=["POST"])
@admin_required
def admin_upload():
    title = request.form.get("title", "").strip()
    artist = request.form.get("artist", "").strip()
    genre = request.form.get("genre", "Other").strip()
    album = request.form.get("album", "").strip()

    audio_file = request.files.get("audio")
    cover_file = request.files.get("cover")

    if not title or not artist or not audio_file:
        return "Title, artist and audio are required.", 400

    audio_ext = Path(audio_file.filename).suffix.lower()

    if audio_ext not in ALLOWED_AUDIO:
        return "Unsupported audio format.", 400

    safe_audio = secure_filename(audio_file.filename)

    if not safe_audio:
        return "Invalid audio filename.", 400

    audio_path = MUSIC_DIR / safe_audio
    audio_file.save(audio_path)

    cover_name = ""

    if cover_file and cover_file.filename:
        cover_ext = Path(cover_file.filename).suffix.lower()

        if cover_ext in ALLOWED_IMAGE:
            cover_name = secure_filename(cover_file.filename)

            if cover_name:
                cover_path = BASE_DIR / "static" / "images" / cover_name
                cover_file.save(cover_path)

    connection = db()

    connection.execute("""
        INSERT INTO songs(
            title,
            artist,
            genre,
            album,
            cover,
            audio
        )
        VALUES (?, ?, ?, ?, ?, ?)
    """, (
        title,
        artist,
        genre,
        album,
        cover_name,
        safe_audio,
    ))

    connection.commit()
    connection.close()

    return redirect(url_for("admin"))


@app.route("/admin/news", methods=["POST"])
@admin_required
def admin_news():
    title = request.form.get("title", "").strip()
    body = request.form.get("body", "").strip()

    if not title or not body:
        return "Title and body are required.", 400

    connection = db()

    connection.execute("""
        INSERT INTO news(title, body)
        VALUES (?, ?)
    """, (title, body))

    connection.commit()
    connection.close()

    return redirect(url_for("admin"))


@app.route("/admin/delete-song/<int:song_id>", methods=["POST"])
@admin_required
def delete_song(song_id):
    connection = db()

    song = connection.execute(
        "SELECT audio FROM songs WHERE id = ?",
        (song_id,)
    ).fetchone()

    if song:
        audio_path = MUSIC_DIR / Path(song["audio"]).name

        if audio_path.exists():
            audio_path.unlink()

        connection.execute(
            "DELETE FROM songs WHERE id = ?",
            (song_id,)
        )

        connection.commit()

    connection.close()

    return redirect(url_for("admin"))


@app.route("/help")
def help_page():
    return render_template("simple_page.html", title="Help")


@app.route("/privacy")
def privacy():
    return render_template("simple_page.html", title="Privacy Policy")


@app.route("/report")
def report():
    return render_template("simple_page.html", title="Report")


@app.route("/legal")
def legal():
    return render_template("simple_page.html", title="Legal & DMCA")


@app.route("/static/music/<path:filename>")
def music_file(filename):
    return send_from_directory(MUSIC_DIR, filename)


if __name__ == "__main__":
    app.run(
        host="127.0.0.1",
        port=5050,
        debug=True,
    )
PY


cat > templates/base.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>{% block title %}ZimPlug Music{% endblock %}</title>

    <link rel="stylesheet"
          href="{{ url_for('static', filename='css/style.css') }}">
</head>

<body>

<header class="site-header">

    <a href="/" class="brand">
        <img src="{{ url_for('static', filename='images/logo.png') }}"
             alt="ZimPlug">
    </a>

    <nav class="main-nav">
        <a href="/" class="{% if request.path == '/' %}active{% endif %}">
            HOME
        </a>

        <a href="/music"
           class="{% if request.path.startswith('/music') %}active{% endif %}">
            MUSIC
        </a>

        <a href="/news"
           class="{% if request.path.startswith('/news') %}active{% endif %}">
            NEWS
        </a>
    </nav>

    <a href="/register" class="header-account">
        CREATE ACCOUNT
    </a>

</header>

{% block content %}{% endblock %}

<footer class="site-footer">

    <div class="footer-logo">
        <img src="{{ url_for('static', filename='images/logo.png') }}"
             alt="ZimPlug">
        <strong>ZIMPLUG OFFICIAL</strong>
    </div>

    <div class="footer-links">
        <a href="/help">HELP</a>
        <a href="/privacy">PRIVACY POLICY</a>
        <a href="/report">REPORT</a>
        <a href="/legal">LEGAL & DMCA</a>
    </div>

    <p>© 2026 ZimPlug Official. All rights reserved.</p>

</footer>

<div class="player" id="player">

    <div class="player-info">
        <div class="player-art" id="playerArt">♪</div>

        <div>
            <strong id="playerTitle">Nothing playing</strong>
            <span id="playerArtist">Choose a song</span>
        </div>
    </div>

    <div class="player-controls">

        <button id="previousButton">↶</button>

        <button class="player-play" id="playButton">▶</button>

        <button id="nextButton">↷</button>

    </div>

    <audio id="audio"></audio>

</div>

<script src="{{ url_for('static', filename='js/player.js') }}"></script>

</body>
</html>
HTML


cat > templates/index.html <<'HTML'
{% extends "base.html" %}

{% block title %}ZimPlug Music — You're Plugged{% endblock %}

{% block content %}

<main>

<section class="hero">

    <div class="hero-inner">

        <span class="eyebrow">ZIMPLUG MUSIC</span>

        <h1>
            YOU'RE<br>
            <span>PLUGGED.</span>
        </h1>

        <p>
            Discover Zimbabwean music, new artists and the sounds
            moving Africa.
        </p>

        <div class="hero-actions">
            <a href="/music" class="gold-button">
                EXPLORE MUSIC
            </a>

            <a href="/register" class="outline-button">
                CREATE ACCOUNT
            </a>
        </div>

    </div>

</section>


<section class="genres-section">

    <div class="section-heading">
        <div>
            <span class="eyebrow">DISCOVER</span>
            <h2>Find your sound.</h2>
        </div>
    </div>

    <div class="genres">

        {% for genre in [
            "AfroSounds",
            "Afrobeats",
            "Hip Hop",
            "Zimdancehall",
            "R&B",
            "Amapiano",
            "Gospel",
            "Dance",
            "Pop",
            "Soul",
            "Reggae"
        ] %}

        <a href="/music?genre={{ genre|urlencode }}"
           class="genre">
            {{ genre }}
            <span>→</span>
        </a>

        {% endfor %}

    </div>

</section>


<section class="music-section">

    <div class="section-heading">

        <div>
            <span class="eyebrow">LISTEN NOW</span>
            <h2>Trending songs.</h2>
        </div>

        <a href="/music">VIEW ALL →</a>

    </div>

    <div class="song-list">

        {% if songs %}

            {% for song in songs %}

            <article class="song-row"
                     data-id="{{ song.id }}"
                     data-audio="{{ url_for('static', filename='music/' + song.audio) }}"
                     data-title="{{ song.title }}"
                     data-artist="{{ song.artist }}"
                     data-cover="{{ url_for('static', filename='images/' + song.cover) if song.cover else '' }}">

                <button class="song-play">
                    ▶
                </button>

                <div class="song-cover">
                    {% if song.cover %}
                        <img src="{{ url_for('static', filename='images/' + song.cover) }}">
                    {% else %}
                        ♪
                    {% endif %}
                </div>

                <div class="song-details">
                    <strong>{{ song.title }}</strong>
                    <span>{{ song.artist }}</span>
                </div>

                <div class="song-meta">
                    <span>{{ song.plays }} plays</span>
                    <span>{{ song.downloads }} downloads</span>
                </div>

                <a href="/download/{{ song.id }}"
                   class="download-button">
                    ↓
                </a>

            </article>

            {% endfor %}

        {% else %}

            <div class="empty-state">
                <strong>No music uploaded yet.</strong>
                <span>New sounds are coming soon.</span>
            </div>

        {% endif %}

    </div>

</section>


<section class="albums-section">

    <div class="section-heading">

        <div>
            <span class="eyebrow">NUMBERS</span>
            <h2>Trending albums.</h2>
        </div>

    </div>

    <div class="album-grid">

        {% for album in albums %}

        <article class="album-card">

            <div class="album-cover">

                {% if album.cover %}

                    <img src="{{ url_for('static', filename='images/' + album.cover) }}">

                {% else %}

                    <span>♪</span>

                {% endif %}

                <div class="album-rank">
                    #{{ loop.index }}
                </div>

            </div>

            <strong>{{ album.album }}</strong>

            <span>{{ album.artist }}</span>

            <small>
                {{ album.plays }} plays ·
                {{ album.downloads }} downloads
            </small>

        </article>

        {% endfor %}

    </div>

</section>


<section class="news-preview">

    <div class="section-heading">

        <div>
            <span class="eyebrow">STAY INFORMED</span>
            <h2>What's happening.</h2>
        </div>

        <a href="/news">ALL NEWS →</a>

    </div>

</section>

</main>

<script src="{{ url_for('static', filename='js/home.js') }}"></script>

{% endblock %}
HTML


cat > templates/music.html <<'HTML'
{% extends "base.html" %}

{% block title %}Music | ZimPlug Music{% endblock %}

{% block content %}

<main class="inner-page">

    <section class="page-heading">

        <span class="eyebrow">ZIMPLUG MUSIC</span>

        <h1>
            All the sounds.<br>
            <span>One place.</span>
        </h1>

        <p>
            Stream Zimbabwean music and discover what's moving.
            Download your favourite songs directly.
        </p>

    </section>


    <section>

        <div class="genre-filter">

            <a href="/music"
               class="{% if not selected_genre %}selected{% endif %}">
                ALL
            </a>

            {% for genre in genres %}

            <a href="/music?genre={{ genre|urlencode }}"
               class="{% if selected_genre|lower == genre|lower %}selected{% endif %}">
                {{ genre|upper }}
            </a>

            {% endfor %}

        </div>


        <div class="song-list">

            {% for song in songs %}

            <article class="song-row"
                     data-id="{{ song.id }}"
                     data-audio="{{ url_for('static', filename='music/' + song.audio) }}"
                     data-title="{{ song.title }}"
                     data-artist="{{ song.artist }}"
                     data-cover="{{ url_for('static', filename='images/' + song.cover) if song.cover else '' }}">

                <button class="song-play">
                    ▶
                </button>

                <div class="song-cover">

                    {% if song.cover %}
                        <img src="{{ url_for('static', filename='images/' + song.cover) }}">
                    {% else %}
                        ♪
                    {% endif %}

                </div>

                <div class="song-details">

                    <strong>{{ song.title }}</strong>

                    <span>
                        {{ song.artist }}
                        {% if song.album %}
                            · {{ song.album }}
                        {% endif %}
                    </span>

                </div>

                <div class="song-meta">
                    <span>{{ song.plays }} plays</span>
                    <span>{{ song.downloads }} downloads</span>
                </div>

                <a href="/download/{{ song.id }}"
                   class="download-button">
                    ↓
                </a>

            </article>

            {% else %}

            <div class="empty-state">
                <strong>No songs found.</strong>
                <span>Try another genre.</span>
            </div>

            {% endfor %}

        </div>

    </section>

</main>

<script src="{{ url_for('static', filename='js/music.js') }}"></script>

{% endblock %}
HTML


cat > templates/news.html <<'HTML'
{% extends "base.html" %}

{% block title %}News | ZimPlug Music{% endblock %}

{% block content %}

<main class="inner-page">

    <section class="page-heading">

        <span class="eyebrow">ZIMPLUG OFFICIAL</span>

        <h1>
            Music.<br>
            <span>News.</span>
        </h1>

        <p>
            News, announcements and updates from ZimPlug Music.
        </p>

    </section>


    <section class="news-grid">

        {% for article in articles %}

        <article class="news-card">

            <span class="eyebrow">
                ZIMPLUG NEWS
            </span>

            <h2>{{ article.title }}</h2>

            <p>{{ article.body }}</p>

            <small>{{ article.created_at }}</small>

        </article>

        {% else %}

        <div class="empty-state">

            <strong>No news yet.</strong>

            <span>
                Check back soon for ZimPlug updates.
            </span>

        </div>

        {% endfor %}

    </section>

</main>

{% endblock %}
HTML


cat > templates/register.html <<'HTML'
{% extends "base.html" %}

{% block title %}Create Account | ZimPlug Music{% endblock %}

{% block content %}

<main class="auth-page">

    <div class="auth-card">

        <span class="eyebrow">ZIMPLUG MUSIC</span>

        <h1>Create your account.</h1>

        <p>
            Join ZimPlug and keep your music discovery experience
            connected.
        </p>

        <form method="POST">

            <label>Name</label>
            <input name="name" required>

            <label>Email</label>
            <input type="email" name="email" required>

            <label>Password</label>
            <input type="password" name="password" required>

            <button class="gold-button" type="submit">
                CREATE ACCOUNT
            </button>

        </form>

    </div>

</main>

{% endblock %}
HTML


cat > templates/admin_login.html <<'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>ZimPlug Admin</title>
    <link rel="stylesheet"
          href="{{ url_for('static', filename='css/style.css') }}">
</head>

<body>

<main class="auth-page">

    <div class="auth-card">

        <span class="eyebrow">ZIMPLUG MUSIC</span>

        <h1>Admin.</h1>

        {% if error %}
            <div class="error">{{ error }}</div>
        {% endif %}

        <form method="POST">

            <label>Username</label>
            <input name="username" required>

            <label>Password</label>
            <input type="password" name="password" required>

            <button class="gold-button">
                ENTER ADMIN
            </button>

        </form>

    </div>

</main>

</body>
</html>
HTML


cat > templates/admin.html <<'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>ZimPlug Admin</title>
    <link rel="stylesheet"
          href="{{ url_for('static', filename='css/style.css') }}">
</head>

<body>

<header class="site-header">

    <a href="/" class="brand">
        <img src="{{ url_for('static', filename='images/logo.png') }}">
    </a>

    <strong>ADMIN</strong>

    <a href="/admin/logout" class="header-account">
        LOG OUT
    </a>

</header>


<main class="admin-page">

    <section class="admin-heading">

        <span class="eyebrow">ZIMPLUG MUSIC</span>

        <h1>Admin Dashboard.</h1>

        <p>
            Upload music and publish news. Public users never receive
            access to these tools.
        </p>

    </section>


    <section class="admin-grid">

        <div class="admin-card">

            <span class="eyebrow">UPLOAD</span>

            <h2>New song</h2>

            <form method="POST"
                  action="/admin/upload"
                  enctype="multipart/form-data">

                <label>Song title</label>
                <input name="title" required>

                <label>Artist</label>
                <input name="artist" required>

                <label>Genre</label>
                <select name="genre">

                    <option>AfroSounds</option>
                    <option>Afrobeats</option>
                    <option>Hip Hop</option>
                    <option>Zimdancehall</option>
                    <option>R&B</option>
                    <option>Amapiano</option>
                    <option>Gospel</option>
                    <option>Dance</option>
                    <option>Pop</option>
                    <option>Soul</option>
                    <option>Reggae</option>
                    <option>Other</option>

                </select>

                <label>Album</label>
                <input name="album">

                <label>Audio</label>
                <input type="file"
                       name="audio"
                       accept=".mp3,.wav,.m4a,.aac,.ogg"
                       required>

                <label>Cover</label>
                <input type="file"
                       name="cover"
                       accept=".jpg,.jpeg,.png,.webp">

                <button class="gold-button">
                    PUBLISH SONG
                </button>

            </form>

        </div>


        <div class="admin-card">

            <span class="eyebrow">NEWS</span>

            <h2>Publish update</h2>

            <form method="POST"
                  action="/admin/news">

                <label>Headline</label>
                <input name="title" required>

                <label>Story</label>
                <textarea name="body" rows="8" required></textarea>

                <button class="gold-button">
                    PUBLISH NEWS
                </button>

            </form>

        </div>

    </section>


    <section class="admin-card">

        <span class="eyebrow">LIBRARY</span>

        <h2>Uploaded music</h2>

        {% for song in songs %}

        <div class="admin-song">

            <div>
                <strong>{{ song.title }}</strong>
                <span>{{ song.artist }}</span>
            </div>

            <div>
                {{ song.plays }} plays ·
                {{ song.downloads }} downloads
            </div>

            <form method="POST"
                  action="/admin/delete-song/{{ song.id }}">

                <button class="delete-button">
                    DELETE
                </button>

            </form>

        </div>

        {% else %}

        <p>No music uploaded yet.</p>

        {% endfor %}

    </section>

</main>

</body>
</html>
HTML


cat > templates/simple_page.html <<'HTML'
{% extends "base.html" %}

{% block title %}{{ title }} | ZimPlug Music{% endblock %}

{% block content %}

<main class="inner-page">

    <section class="page-heading">

        <span class="eyebrow">ZIMPLUG OFFICIAL</span>

        <h1>{{ title }}.</h1>

        <p>
            ZimPlug Music is built to make discovering and downloading
            music simple.
        </p>

    </section>

</main>

{% endblock %}
HTML


cat > static/js/player.js <<'JS'
(function () {

    const audio = document.getElementById("audio");
    const player = document.getElementById("player");

    const title = document.getElementById("playerTitle");
    const artist = document.getElementById("playerArtist");
    const art = document.getElementById("playerArt");

    const playButton = document.getElementById("playButton");
    const previousButton = document.getElementById("previousButton");
    const nextButton = document.getElementById("nextButton");

    let queue = [];
    let currentIndex = -1;

    function getRows() {
        return Array.from(
            document.querySelectorAll(".song-row")
        );
    }

    function playSong(row) {

        if (!row) return;

        const id = row.dataset.id;
        const audioFile = row.dataset.audio;

        if (!audioFile) return;

        queue = getRows();

        currentIndex = queue.indexOf(row);

        audio.src = audioFile;

        title.textContent = row.dataset.title || "Unknown Track";
        artist.textContent = row.dataset.artist || "Unknown Artist";

        if (row.dataset.cover) {
            art.innerHTML =
                '<img src="' +
                row.dataset.cover +
                '" alt="">';
        } else {
            art.textContent = "♪";
        }

        player.classList.add("visible");

        document.querySelectorAll(".song-row.playing")
            .forEach(function (item) {
                item.classList.remove("playing");
            });

        row.classList.add("playing");

        audio.play()
            .then(function () {

                playButton.textContent = "❚❚";

                fetch("/play/" + id, {
                    method: "POST"
                }).catch(function () {});

            })
            .catch(function (error) {
                console.error("Playback failed:", error);
            });
    }


    function togglePlay() {

        if (!audio.src) {

            const rows = getRows();

            if (rows.length) {
                playSong(rows[0]);
            }

            return;
        }

        if (audio.paused) {

            audio.play();
            playButton.textContent = "❚❚";

        } else {

            audio.pause();
            playButton.textContent = "▶";

        }

    }


    function nextSong() {

        if (!queue.length) {
            queue = getRows();
        }

        if (!queue.length) return;

        currentIndex++;

        if (currentIndex >= queue.length) {
            currentIndex = 0;
        }

        playSong(queue[currentIndex]);
    }


    function previousSong() {

        if (!queue.length) {
            queue = getRows();
        }

        if (!queue.length) return;

        currentIndex--;

        if (currentIndex < 0) {
            currentIndex = queue.length - 1;
        }

        playSong(queue[currentIndex]);
    }


    document.addEventListener("click", function (event) {

        const button = event.target.closest(".song-play");

        if (!button) return;

        const row = button.closest(".song-row");

        playSong(row);

    });


    playButton.addEventListener(
        "click",
        togglePlay
    );

    nextButton.addEventListener(
        "click",
        nextSong
    );

    previousButton.addEventListener(
        "click",
        previousSong
    );


    audio.addEventListener("play", function () {
        playButton.textContent = "❚❚";
    });


    audio.addEventListener("pause", function () {
        playButton.textContent = "▶";
    });


    audio.addEventListener("ended", function () {
        nextSong();
    });


})();
JS


cat > static/js/home.js <<'JS'
(function () {

    const rows = document.querySelectorAll(".song-row");

    rows.forEach(function (row) {

        const button = row.querySelector(".song-play");

        if (!button) return;

        button.addEventListener("click", function () {
            // Global player handles playback.
        });

    });

})();
JS


cat > static/js/music.js <<'JS'
(function () {

    // Music page intentionally uses the global ZimPlug player.
    // This prevents multiple audio elements from playing at once.

})();
JS


cat > static/css/style.css <<'CSS'
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap');

:root {
    --black: #050505;
    --dark: #0b0b0b;
    --panel: #101010;
    --gold: #d4af37;
    --gold-light: #f1ce58;
    --white: #ffffff;
    --muted: #858585;
    --line: rgba(255,255,255,.08);
}

* {
    box-sizing: border-box;
}

html {
    scroll-behavior: smooth;
}

body {
    margin: 0;
    background: var(--black);
    color: var(--white);
    font-family: Inter, Arial, sans-serif;
}

a {
    color: inherit;
    text-decoration: none;
}

button,
input,
textarea,
select {
    font: inherit;
}

.site-header {
    height: 82px;
    padding: 0 5%;
    display: grid;
    grid-template-columns: 180px 1fr 180px;
    align-items: center;
    border-bottom: 1px solid var(--line);
    background: rgba(5,5,5,.96);
    position: relative;
    z-index: 100;
}

.brand img {
    width: 105px;
    display: block;
}

.main-nav {
    display: flex;
    justify-content: center;
    gap: 45px;
}

.main-nav a {
    color: #777;
    font-size: 10px;
    font-weight: 800;
    letter-spacing: 2px;
    transition: .2s;
}

.main-nav a:hover,
.main-nav a.active {
    color: var(--gold);
}

.header-account {
    justify-self: end;
    border: 1px solid rgba(212,175,55,.5);
    padding: 12px 17px;
    color: var(--gold);
    font-size: 9px;
    font-weight: 800;
    letter-spacing: 1px;
}

.hero {
    min-height: 650px;
    display: flex;
    justify-content: center;
    align-items: center;
    text-align: center;
    padding: 90px 20px;
    background:
        radial-gradient(
            circle at center,
            rgba(212,175,55,.12),
            transparent 38%
        ),
        radial-gradient(
            circle at 15% 50%,
            rgba(255,255,255,.035),
            transparent 30%
        ),
        linear-gradient(
            180deg,
            #0b0b0b 0%,
            #050505 100%
        );
}

.hero-inner {
    max-width: 850px;
}

.eyebrow {
    color: var(--gold);
    font-size: 9px;
    font-weight: 900;
    letter-spacing: 3px;
}

.hero h1 {
    margin: 22px 0;
    font-size: clamp(65px, 11vw, 145px);
    line-height: .82;
    letter-spacing: -8px;
    font-weight: 900;
}

.hero h1 span,
.page-heading h1 span {
    color: var(--gold);
}

.hero p {
    max-width: 560px;
    margin: 0 auto 35px;
    color: #888;
    line-height: 1.8;
    font-size: 14px;
}

.hero-actions {
    display: flex;
    justify-content: center;
    gap: 12px;
}

.gold-button,
.outline-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: 0;
    cursor: pointer;
    padding: 15px 24px;
    font-size: 9px;
    font-weight: 900;
    letter-spacing: 1.5px;
}

.gold-button {
    background: var(--gold);
    color: #050505;
}

.gold-button:hover {
    background: var(--gold-light);
}

.outline-button {
    border: 1px solid #333;
    color: #aaa;
    background: transparent;
}

.outline-button:hover {
    border-color: var(--gold);
    color: var(--gold);
}

.genres-section,
.music-section,
.albums-section,
.news-preview,
.inner-page {
    max-width: 1250px;
    margin: auto;
    padding: 80px 5%;
}

.section-heading {
    display: flex;
    justify-content: space-between;
    align-items: end;
    margin-bottom: 30px;
}

.section-heading h2 {
    margin: 10px 0 0;
    font-size: 36px;
    letter-spacing: -2px;
}

.section-heading > a {
    color: var(--gold);
    font-size: 9px;
    font-weight: 900;
    letter-spacing: 1.5px;
}

.genres {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    border-top: 1px solid var(--line);
    border-left: 1px solid var(--line);
}

.genre {
    padding: 23px;
    border-right: 1px solid var(--line);
    border-bottom: 1px solid var(--line);
    color: #aaa;
    font-size: 12px;
    font-weight: 700;
    display: flex;
    justify-content: space-between;
    transition: .2s;
}

.genre span {
    color: #444;
}

.genre:hover {
    color: var(--gold);
    background: #0d0d0d;
}

.song-list {
    border-top: 1px solid var(--line);
}

.song-row {
    min-height: 78px;
    display: grid;
    grid-template-columns: 38px 58px 1fr auto 40px;
    align-items: center;
    gap: 15px;
    border-bottom: 1px solid var(--line);
    transition: .2s;
}

.song-row:hover,
.song-row.playing {
    background: #0d0d0d;
}

.song-play {
    width: 30px;
    height: 30px;
    border-radius: 50%;
    border: 1px solid #333;
    background: transparent;
    color: #aaa;
    cursor: pointer;
}

.song-row:hover .song-play,
.song-row.playing .song-play {
    background: var(--gold);
    border-color: var(--gold);
    color: #050505;
}

.song-cover,
.player-art {
    width: 50px;
    height: 50px;
    background: #151515;
    display: flex;
    justify-content: center;
    align-items: center;
    overflow: hidden;
    color: var(--gold);
}

.song-cover img,
.player-art img {
    width: 100%;
    height: 100%;
    object-fit: cover;
}

.song-details {
    display: flex;
    flex-direction: column;
    gap: 6px;
}

.song-details strong {
    font-size: 13px;
}

.song-details span {
    color: #666;
    font-size: 10px;
}

.song-meta {
    display: flex;
    gap: 18px;
    color: #555;
    font-size: 9px;
}

.download-button {
    color: #777;
    font-size: 20px;
    text-align: center;
}

.download-button:hover {
    color: var(--gold);
}

.album-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 20px;
}

.album-card {
    min-width: 0;
}

.album-cover {
    aspect-ratio: 1;
    position: relative;
    background: #111;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--gold);
    font-size: 45px;
    margin-bottom: 15px;
    overflow: hidden;
}

.album-cover img {
    width: 100%;
    height: 100%;
    object-fit: cover;
}

.album-rank {
    position: absolute;
    left: 10px;
    top: 10px;
    padding: 8px 10px;
    background: rgba(0,0,0,.8);
    color: var(--gold);
    font-size: 9px;
    font-weight: 900;
}

.album-card > strong,
.album-card > span,
.album-card > small {
    display: block;
}

.album-card strong {
    font-size: 14px;
}

.album-card span {
    margin-top: 5px;
    color: #777;
    font-size: 10px;
}

.album-card small {
    margin-top: 10px;
    color: #444;
    font-size: 9px;
}

.site-footer {
    padding: 70px 5% 110px;
    border-top: 1px solid var(--line);
    text-align: center;
}

.footer-logo {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 15px;
}

.footer-logo img {
    width: 100px;
}

.footer-logo strong {
    color: var(--gold);
    font-size: 9px;
    letter-spacing: 3px;
}

.footer-links {
    margin: 35px 0;
    display: flex;
    justify-content: center;
    flex-wrap: wrap;
    gap: 25px;
}

.footer-links a {
    color: #555;
    font-size: 9px;
    font-weight: 800;
}

.footer-links a:hover {
    color: var(--gold);
}

.site-footer p {
    color: #333;
    font-size: 9px;
}

.page-heading {
    padding: 70px 0;
    border-bottom: 1px solid var(--line);
}

.page-heading h1 {
    margin: 15px 0;
    font-size: clamp(55px, 8vw, 100px);
    line-height: .9;
    letter-spacing: -5px;
}

.page-heading p {
    max-width: 600px;
    color: #777;
    line-height: 1.8;
}

.genre-filter {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin: 45px 0;
}

.genre-filter a {
    padding: 11px 14px;
    border: 1px solid #222;
    color: #666;
    font-size: 8px;
    font-weight: 800;
    letter-spacing: 1px;
}

.genre-filter a:hover,
.genre-filter a.selected {
    border-color: var(--gold);
    color: var(--gold);
}

.news-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 20px;
}

.news-card,
.admin-card {
    background: #0c0c0c;
    border: 1px solid var(--line);
    padding: 35px;
}

.news-card h2 {
    margin: 15px 0;
    font-size: 28px;
}

.news-card p {
    color: #777;
    line-height: 1.8;
    white-space: pre-line;
}

.news-card small {
    color: #444;
    font-size: 9px;
}

.auth-page {
    min-height: calc(100vh - 82px);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 60px 20px;
}

.auth-card {
    width: 100%;
    max-width: 470px;
    background: #0c0c0c;
    border: 1px solid var(--line);
    padding: 45px;
}

.auth-card h1 {
    font-size: 40px;
    margin: 15px 0;
}

.auth-card p {
    color: #777;
    line-height: 1.7;
}

form {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

form label {
    margin-top: 10px;
    color: #888;
    font-size: 9px;
    font-weight: 800;
    letter-spacing: 1px;
    text-transform: uppercase;
}

input,
textarea,
select {
    width: 100%;
    padding: 14px;
    border: 1px solid #252525;
    outline: none;
    background: #080808;
    color: white;
}

input:focus,
textarea:focus,
select:focus {
    border-color: var(--gold);
}

.player {
    position: fixed;
    left: 20px;
    right: 20px;
    bottom: 18px;
    z-index: 9999;
    min-height: 70px;
    padding: 10px 18px;
    background: rgba(12,12,12,.97);
    border: 1px solid rgba(212,175,55,.2);
    backdrop-filter: blur(20px);
    display: none;
    grid-template-columns: 1fr auto;
    align-items: center;
    box-shadow: 0 20px 60px rgba(0,0,0,.6);
}

.player.visible {
    display: grid;
}

.player-info {
    display: flex;
    align-items: center;
    gap: 13px;
}

.player-info strong,
.player-info span {
    display: block;
}

.player-info strong {
    font-size: 11px;
}

.player-info span {
    color: #666;
    font-size: 9px;
    margin-top: 4px;
}

.player-controls {
    display: flex;
    align-items: center;
    gap: 10px;
}

.player-controls button {
    width: 32px;
    height: 32px;
    border: 0;
    background: transparent;
    color: #888;
    cursor: pointer;
}

.player-controls button:hover {
    color: var(--gold);
}

.player-play {
    border-radius: 50% !important;
    background: var(--gold) !important;
    color: #050505 !important;
}

.admin-page {
    max-width: 1250px;
    margin: auto;
    padding: 70px 5% 120px;
}

.admin-heading {
    margin-bottom: 45px;
}

.admin-heading h1 {
    font-size: 65px;
    letter-spacing: -4px;
}

.admin-heading p {
    color: #777;
}

.admin-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 20px;
    margin-bottom: 20px;
}

.admin-card h2 {
    margin: 10px 0 30px;
}

.admin-song {
    min-height: 65px;
    border-top: 1px solid var(--line);
    display: grid;
    grid-template-columns: 1fr auto auto;
    align-items: center;
    gap: 20px;
}

.admin-song strong,
.admin-song span {
    display: block;
}

.admin-song span {
    color: #666;
    font-size: 10px;
    margin-top: 5px;
}

.delete-button {
    border: 1px solid #422;
    background: transparent;
    color: #c66;
    padding: 8px 12px;
    cursor: pointer;
    font-size: 8px;
}

.empty-state {
    padding: 50px 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
}

.empty-state strong {
    font-size: 14px;
}

.empty-state span {
    color: #555;
    font-size: 11px;
}

.error {
    padding: 12px;
    margin-bottom: 15px;
    border: 1px solid #522;
    color: #d88;
    font-size: 11px;
}

@media (max-width: 850px) {

    .site-header {
        grid-template-columns: 100px 1fr;
        height: 70px;
    }

    .brand img {
        width: 80px;
    }

    .main-nav {
        gap: 18px;
    }

    .header-account {
        display: none;
    }

    .genres {
        grid-template-columns: repeat(2, 1fr);
    }

    .album-grid {
        grid-template-columns: repeat(2, 1fr);
    }

    .admin-grid,
    .news-grid {
        grid-template-columns: 1fr;
    }

    .song-row {
        grid-template-columns: 34px 48px 1fr 35px;
    }

    .song-meta {
        display: none;
    }

    .player {
        left: 8px;
        right: 8px;
        bottom: 8px;
    }

}

@media (max-width: 550px) {

    .main-nav {
        gap: 12px;
    }

    .main-nav a {
        font-size: 8px;
        letter-spacing: 1px;
    }

    .hero {
        min-height: 570px;
    }

    .hero h1 {
        letter-spacing: -5px;
    }

    .hero-actions {
        flex-direction: column;
        max-width: 250px;
        margin: auto;
    }

    .section-heading h2 {
        font-size: 28px;
    }

    .genres-section,
    .music-section,
    .albums-section,
    .news-preview,
    .inner-page {
        padding-left: 20px;
        padding-right: 20px;
    }

    .song-row {
        gap: 9px;
        grid-template-columns: 30px 45px 1fr 30px;
    }

    .song-cover {
        width: 45px;
        height: 45px;
    }

    .song-details strong {
        font-size: 11px;
    }

    .song-details span {
        font-size: 8px;
    }

    .album-grid {
        gap: 12px;
    }

    .auth-card {
        padding: 30px 22px;
    }

}
CSS


echo ""
echo "=========================================="
echo " ZIMPLUG MUSIC CREATED"
echo "=========================================="
echo ""
echo "Install:"
echo "  python3 -m venv venv"
echo "  source venv/bin/activate"
echo "  pip install -r requirements.txt"
echo ""
echo "Start:"
echo "  python app.py"
echo ""
echo "Public:"
echo "  http://127.0.0.1:5050"
echo ""
echo "Admin:"
echo "  http://127.0.0.1:5050/admin/login"
echo ""
echo "Default admin:"
echo "  username: admin"
echo "  password: zimplug123"
echo ""
