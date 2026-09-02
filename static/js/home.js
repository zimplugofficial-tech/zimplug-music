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
