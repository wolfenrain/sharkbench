const http = require('http');
const url = require('url');

const PORT = 3000;

function calcPi(iterations) {
    let pi = 0.0;
    let denominator = 1.0;
    for (let x = 0; x < iterations; x++) {
        if (x % 2 === 0) {
            pi = pi + (1 / denominator);
        } else {
            pi = pi - (1 / denominator);
        }
        denominator = denominator + 2;
    }
    pi = pi * 4;
    return pi;
}

const server = http.createServer((req, res) => {
    const queryObject = url.parse(req.url, true).query;
    let iterations = parseInt(queryObject.iterations, 10) || 1;

    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`${calcPi(iterations)}`);
});

server.listen(PORT, () => {
    console.log(`Server listening on port ${PORT}`);
});
