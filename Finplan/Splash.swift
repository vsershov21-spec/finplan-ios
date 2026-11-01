import UIKit

/// Заставка поверх сайта: продолжает экран запуска (тот же логотип на том же месте), пока сайт не готов.
/// Затем логотип мягко увеличивается и растворяется — как в приложениях Apple, без белой вспышки.
final class SplashView: UIView {
    private let logo = UIImageView(image: UIImage(named: "Logo"))
    private let kuzya = UIImageView(image: UIImage(named: "Kuzya-wait"))
    private let line = UILabel()
    private var timer: Timer?
    private var i = 0
    private static let phrases = ["Кузьма пересчитывает монетки", "Сверяю счета", "Раскладываю по целям", "Смотрю, что впереди"]

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(named: "Paper")
        logo.contentMode = .center
        kuzya.contentMode = .scaleAspectFit; kuzya.alpha = 0
        line.font = .systemFont(ofSize: 14, weight: .medium); line.textColor = .secondaryLabel; line.textAlignment = .center; line.alpha = 0
        for v in [logo, kuzya, line] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: centerXAnchor), logo.centerYAnchor.constraint(equalTo: centerYAnchor),
            kuzya.centerXAnchor.constraint(equalTo: centerXAnchor), kuzya.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 36),
            kuzya.widthAnchor.constraint(equalToConstant: 64), kuzya.heightAnchor.constraint(equalToConstant: 64),
            line.centerXAnchor.constraint(equalTo: centerXAnchor), line.topAnchor.constraint(equalTo: kuzya.bottomAnchor, constant: 10)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(in host: UIView) {
        frame = host.bounds; autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(self)
        // если сайт грузится дольше полсекунды — появляется Кузьма и короткие фразы
        line.text = Self.phrases[0]
        UIView.animate(withDuration: 0.4, delay: 0.6, options: .curveEaseOut) { self.kuzya.alpha = 1; self.line.alpha = 1 }
        let breathe = CABasicAnimation(keyPath: "transform.scale"); breathe.fromValue = 1; breathe.toValue = 1.04; breathe.duration = 1.2
        breathe.autoreverses = true; breathe.repeatCount = .infinity; breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        logo.layer.add(breathe, forKey: "breathe")
        timer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.i = (self.i + 1) % Self.phrases.count
            UIView.transition(with: self.line, duration: 0.3, options: .transitionCrossDissolve) { self.line.text = Self.phrases[self.i] }
        }
    }

    func hide() {
        guard superview != nil, timer != nil || alpha == 1 else { return }
        timer?.invalidate(); timer = nil
        logo.layer.removeAllAnimations()
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.curveEaseOut]) {
            self.logo.transform = CGAffineTransform(scaleX: 1.6, y: 1.6); self.logo.alpha = 0
            self.kuzya.transform = CGAffineTransform(translationX: 0, y: 24); self.kuzya.alpha = 0; self.line.alpha = 0
            self.alpha = 0
        } completion: { _ in self.removeFromSuperview() }
    }
}
