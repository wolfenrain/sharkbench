use axum::{extract::{Query}, routing::get, Router};
use serde::{Deserialize};

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(handler));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

#[derive(Deserialize)]
struct BenchmarkQuery {
    iterations: usize,
}

async fn handler(
    query: Query<BenchmarkQuery>,
) -> String {
    let result = calc_pi(query.iterations);
    format!("{};{};{}", result.0, result.1, result.2)
}

fn calc_pi(iterations: usize) -> (f64, f64, f64) {
    let mut pi = 0.0;
    let mut denominator = 1.0;
    let mut total_sum = 0.0;
    let mut alternating_sum = 0.0;
    for x in 0..iterations {
        if x % 2 == 0 {
            pi = pi + (1.0 / denominator);
        } else {
            pi = pi - (1.0 / denominator);
        }
        denominator = denominator + 2.0;

        // custom
        total_sum = total_sum + pi;
        match x % 3 {
            0 => alternating_sum = alternating_sum + pi,
            1 => alternating_sum = alternating_sum - pi,
            _ => alternating_sum /= 2.0,
        }
    }
    (pi * 4.0, total_sum, alternating_sum)
}
