using System.Collections.Concurrent;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls("http://0.0.0.0:5000");

var app = builder.Build();

var clients = new ConcurrentDictionary<string, ClientConnection>();
var webSocketApp = new Ws(clients);
    `
app.UseWebSockets();

app.MapGet("/", () => "Game server running");
app.Map("/ws", webSocketApp.RunWebSocketApp);

app.Run();
