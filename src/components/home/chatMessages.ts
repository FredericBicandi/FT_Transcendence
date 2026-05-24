export type ChatMessage = {
  id: string;
  sentAt: string;
  username: string;
  text: string;
};

const usernameColors = [
  "#f5dfad",
  "#d9b46b",
  "#7dd3fc",
  "#86efac",
  "#fca5a5",
  "#c4b5fd",
  "#f9a8d4",
  "#fde047",
];

export const dummyChatMessages: ChatMessage[] = [
  {
    id: "dummy-1",
    sentAt: "14:19",
    username: "MossKnight",
    text: "mid bridge is clear",
  },
  {
    id: "dummy-2",
    sentAt: "14:21",
    username: "Guest4821",
    text: "need backup near spawn",
  },
  {
    id: "dummy-3",
    sentAt: "14:24",
    username: "PixelMage",
    text: "holding top wall",
  },
  {
    id: "dummy-4",
    sentAt: "14:27",
    username: "MossKnight",
    text: "two players coming right side",
  },
  {
    id: "dummy-5",
    sentAt: "14:28",
    username: "StoneRunner",
    text: "got it",
  },
];

export function getUsernameColor(username: string) {
  let hash = 0;

  for (let index = 0; index < username.length; index += 1) {
    hash = (hash + username.charCodeAt(index) * (index + 1)) % 997;
  }

  return usernameColors[hash % usernameColors.length];
}

export function getCurrentTime() {
  return new Intl.DateTimeFormat("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date());
}
