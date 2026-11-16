const grid = document.getElementById("sound-grid");
const statusText = document.getElementById("status");
const search = document.getElementById("search");

let sounds = [];
let lastSignature = "";
let loading = false;

function setStatus(message) {
    statusText.textContent = message;
}

async function api(endpoint, data = {}) {
    const response = await fetch(endpoint, {
        method: "POST",
        cache: "no-store",
        headers: {
            "Content-Type": "application/json",
            "X-PYBOARD-TOKEN": window.PYBOARD_TOKEN
        },
        body: JSON.stringify(data)
    });

    const result = await response.json();

    if (!response.ok) {
        throw new Error(result.error || "Request failed");
    }

    return result;
}

async function loadSounds(silent = false) {
    if (loading) return;
    loading = true;

    try {
        const response = await fetch(`/api/sounds?t=${Date.now()}`, {
            cache: "no-store"
        });

        if (!response.ok) {
            throw new Error("Could not load sounds");
        }

        const updatedSounds = await response.json();
        const signature = JSON.stringify(updatedSounds);

        if (signature !== lastSignature) {
            sounds = updatedSounds;
            lastSignature = signature;
            renderSounds();
        }

        if (!silent) {
            setStatus(`${sounds.length} sounds available`);
        } else if (document.visibilityState === "visible") {
            setStatus(`${sounds.length} sounds available`);
        }
    } catch (error) {
        if (!silent) {
            setStatus(error.message);
        }
    } finally {
        loading = false;
    }
}

function renderSounds() {
    grid.replaceChildren();

    const query = search.value.toLowerCase();

    const filtered = sounds.filter(sound =>
        sound.name.toLowerCase().includes(query)
    );

    if (filtered.length === 0) {
        const empty = document.createElement("div");
        empty.className = "empty";
        empty.textContent = sounds.length
            ? "No sounds match your search."
            : "♫ No sounds yet! Download some sounds using PYBOARD.";

        grid.appendChild(empty);
        return;
    }

    for (const sound of filtered) {
        const card = document.createElement("div");
        card.className = "sound-card";

        const icon = document.createElement("div");
        icon.className = "sound-icon";
        icon.textContent = "♫";

        const name = document.createElement("div");
        name.className = "sound-name";
        name.textContent = sound.name;

        const actions = document.createElement("div");
        actions.className = "sound-actions";

        const play = document.createElement("button");
        play.className = "play-button";
        play.textContent = "▶ PLAY";
        play.addEventListener("click", () => playSound(sound.file));

        const remove = document.createElement("button");
        remove.className = "delete-button";
        remove.textContent = "DELETE";
        remove.addEventListener("click", () => deleteSound(sound.file));

        actions.append(play, remove);
        card.append(icon, name, actions);
        grid.appendChild(card);
    }
}

async function playSound(file) {
    try {
        await api("/api/play", { file });
        setStatus("Playing: " + file.replace(".mp3", ""));
    } catch (error) {
        setStatus(error.message);
    }
}

async function stopSound() {
    try {
        await api("/api/stop");
        setStatus("Playback stopped");
    } catch (error) {
        setStatus(error.message);
    }
}

async function deleteSound(file) {
    if (!confirm(`Are you sure you want to delete ${file}?`)) {
        return;
    }

    try {
        await api("/api/delete", { file });
        setStatus("Sound deleted");
        await loadSounds();
    } catch (error) {
        setStatus(error.message);
    }
}

search.addEventListener("input", renderSounds);

document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
        loadSounds();
    }
});

loadSounds();
setInterval(() => {
    if (document.visibilityState === "visible") {
        loadSounds(true);
    }
}, 2500);
