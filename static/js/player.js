(function () {

    let audio;
    let player;
    let title;
    let artist;
    let art;
    let playButton;
    let previousButton;
    let nextButton;

    let queue = [];
    let currentIndex = -1;
    let currentSongId = null;

    function init() {

        audio = document.getElementById("audio");
        player = document.getElementById("player");

        title = document.getElementById("playerTitle");
        artist = document.getElementById("playerArtist");
        art = document.getElementById("playerArt");

        playButton = document.getElementById("playButton");
        previousButton = document.getElementById("previousButton");
        nextButton = document.getElementById("nextButton");

        if (!audio || !player || !playButton) {
            console.error("ZimPlug player elements not found.");
            return;
        }

        updateQueue();
        updatePlayerButton();

        /*
         * SONG BUTTONS
         *
         * This listener is attached to document rather than the Music page.
         * Therefore it continues working after Home/Music/News navigation.
         */
        document.addEventListener("click", function (event) {

            const button = event.target.closest(".song-play");

            if (!button) return;

            const row = button.closest(".song-row");

            if (!row) return;

            event.preventDefault();

            playSong(row);
        });

        playButton.addEventListener("click", function () {
            togglePlay();
        });

        if (nextButton) {
            nextButton.addEventListener("click", function () {
                nextSong();
            });
        }

        if (previousButton) {
            previousButton.addEventListener("click", function () {
                previousSong();
            });
        }

        audio.addEventListener("play", function () {
            updatePlayerButton();
            updateCurrentRow();
        });

        audio.addEventListener("pause", function () {
            updatePlayerButton();
            updateCurrentRow();
        });

        audio.addEventListener("ended", function () {
            nextSong();
        });

        /*
         * This is called after Home/Music/News content is changed.
         * The audio element itself is NEVER recreated.
         */
        window.addEventListener("zimplug:pagechange", function () {
            updateQueue();
            updateCurrentRow();
        });
    }


    function getRows() {
        return Array.from(document.querySelectorAll(".song-row"));
    }


    function updateQueue() {

        const rows = getRows();

        /*
         * If we're on Music, use the visible songs as the queue.
         */
        if (rows.length) {

            queue = rows;

            if (currentSongId !== null) {

                const matchingIndex = queue.findIndex(function (row) {
                    return String(row.dataset.id) === String(currentSongId);
                });

                if (matchingIndex !== -1) {
                    currentIndex = matchingIndex;
                }
            }

        }
    }


    function updatePlayerButton() {

        if (!playButton || !audio) return;

        playButton.textContent = audio.paused ? "▶" : "❚❚";

        playButton.setAttribute(
            "aria-label",
            audio.paused ? "Play" : "Pause"
        );
    }


    function updateCurrentRow() {

        const rows = getRows();

        rows.forEach(function (row) {

            const button = row.querySelector(".song-play");

            row.classList.remove("playing");

            if (button) {
                button.textContent = "▶";
                button.setAttribute("aria-label", "Play");
            }
        });

        if (!currentSongId || audio.paused) {
            return;
        }

        const activeRow = rows.find(function (row) {
            return String(row.dataset.id) === String(currentSongId);
        });

        if (!activeRow) {
            return;
        }

        activeRow.classList.add("playing");

        const button = activeRow.querySelector(".song-play");

        if (button) {
            button.textContent = "❚❚";
            button.setAttribute("aria-label", "Pause");
        }
    }


    function playSong(row) {

        if (!row) return;

        const audioFile = row.dataset.audio;

        if (!audioFile) {
            console.error("No audio file found.");
            return;
        }

        updateQueue();

        const songId = row.dataset.id;
        const requestedUrl =
            new URL(audioFile, window.location.href).href;

        const currentUrl = audio.src
            ? new URL(audio.src, window.location.href).href
            : "";

        /*
         * SAME SONG
         *
         * Clicking the same song toggles pause/resume.
         */
        if (
            currentSongId !== null &&
            String(currentSongId) === String(songId) &&
            currentUrl === requestedUrl
        ) {

            if (audio.paused) {

                audio.play().catch(function (error) {
                    console.error("Playback failed:", error);
                });

            } else {

                audio.pause();
            }

            return;
        }

        /*
         * DIFFERENT SONG
         *
         * Switch immediately and start playing.
         */
        currentSongId = songId;

        const index = queue.findIndex(function (item) {
            return String(item.dataset.id) === String(songId);
        });

        if (index !== -1) {
            currentIndex = index;
        }

        audio.pause();

        audio.src = audioFile;

        title.textContent =
            row.dataset.title || "Unknown Track";

        artist.textContent =
            row.dataset.artist || "Unknown Artist";

        if (row.dataset.cover) {

            art.innerHTML =
                '<img src="' +
                row.dataset.cover +
                '" alt="">';

        } else {

            art.textContent = "♪";
        }

        player.classList.add("visible");

        updateCurrentRow();

        audio.load();

        audio.play()
            .then(function () {

                updatePlayerButton();
                updateCurrentRow();

                if (songId) {

                    fetch("/play/" + songId, {
                        method: "POST"
                    }).catch(function () {});
                }

            })
            .catch(function (error) {

                console.error("Playback failed:", error);

                updatePlayerButton();
                updateCurrentRow();
            });
    }


    function togglePlay() {

        if (!audio.src) {

            updateQueue();

            if (queue.length) {
                playSong(queue[0]);
            }

            return;
        }

        if (audio.paused) {

            audio.play()
                .then(function () {
                    updatePlayerButton();
                    updateCurrentRow();
                })
                .catch(function (error) {
                    console.error("Playback failed:", error);
                });

        } else {

            audio.pause();
        }
    }


    function nextSong() {

        updateQueue();

        if (!queue.length) return;

        currentIndex++;

        if (currentIndex >= queue.length) {
            currentIndex = 0;
        }

        playSong(queue[currentIndex]);
    }


    function previousSong() {

        updateQueue();

        if (!queue.length) return;

        if (audio.currentTime > 3) {

            audio.currentTime = 0;

            return;
        }

        currentIndex--;

        if (currentIndex < 0) {
            currentIndex = queue.length - 1;
        }

        playSong(queue[currentIndex]);
    }


    /*
     * Expose player controls globally.
     */
    window.zimplugPlaySong = playSong;


    /*
     * Start only once.
     */
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }

})();
