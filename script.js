var music = document.getElementById("backgroundMusic");
var musicButton = document.getElementById("musicButton");
var isPlaying = false; // Assume music is not playing initially

document.addEventListener('DOMContentLoaded', function() {
    music.play().then(() => {
        isPlaying = true;
        musicButton.style.opacity = "1"; // Full opacity if playing
        musicButton.style.animationPlayState = 'running'; // Start rotation
    }).catch(error => {
        console.error("Auto-play was prevented by the browser: ", error);
        musicButton.style.opacity = "0.5"; // Lower opacity to indicate not playing
        musicButton.style.animationPlayState = 'paused'; // Keep paused
    });
});

function toggleMusicAndAnimation() {
    if (isPlaying) {
        music.pause();
        musicButton.style.animationPlayState = 'paused'; // Pause the rotation
        musicButton.style.opacity = "0.5"; // Lower opacity
        isPlaying = false;
    } else {
        music.play();
        musicButton.style.animationPlayState = 'running'; // Resume the rotation
        musicButton.style.opacity = "1"; // Full opacity
        isPlaying = true;
    }
}
