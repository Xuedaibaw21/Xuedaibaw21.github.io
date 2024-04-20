var index = 0;
var slides = document.getElementsByClassName("slides");
var music = document.getElementById("backgroundMusic");
var musicButton = document.getElementById("musicButton");
var modal = document.getElementById("qrModal");
var closeButton = document.getElementsByClassName("close-button")[0];

function toggleMusicAndAnimation() {
    if (music.paused) {
        music.play();
        musicButton.style.opacity = "1";
        musicButton.style.animationPlayState = 'running';
    } else {
        music.pause();
        musicButton.style.opacity = "0.5";
        musicButton.style.animationPlayState = 'paused';
    }
}

function showSlides() {
    for (var i = 0; i < slides.length; i++) {
        slides[i].style.display = "none";
    }
    index++;
    if (index > slides.length) {index = 1}
    slides[index-1].style.display = "block";
    setTimeout(showSlides, 3000); // Change image every 3 seconds
}

showSlides(); // Call the function

document.getElementById("contactButton").addEventListener('click', function() {
    modal.style.display = "block";
});

closeButton.addEventListener('click', function() {
    modal.style.display = "none";
});

window.addEventListener('click', function(event) {
    if (event.target == modal) {
        modal.style.display = "none";
    }
});