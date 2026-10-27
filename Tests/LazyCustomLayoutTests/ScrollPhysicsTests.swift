import Testing
@testable import LazyCustomLayout

@Suite("ScrollPhysics.Deceleration")
struct ScrollPhysicsDecelerationTests {

    @Test("velocity at t=0 equals the initial velocity")
    func velocityAtZero() {
        let v = ScrollPhysics.velocity(initialVelocity: 1200, rate: .normal, at: 0)

        #expect(v == 1200)
    }

    @Test("position at t=0 equals the initial position")
    func positionAtZero() {
        let x = ScrollPhysics.position(initialPosition: 50, initialVelocity: 1200, rate: .normal, at: 0)

        #expect(x == 50)
    }

    @Test("velocity magnitude decays monotonically over time")
    func velocityDecaysMonotonically() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.05).map {
            abs(ScrollPhysics.velocity(initialVelocity: 1500, rate: .normal, at: $0))
        }

        for (previous, next) in zip(samples, samples.dropFirst()) {
            #expect(next < previous)
        }
    }

    @Test("fast deceleration decays quicker than normal")
    func fastDecaysQuickerThanNormal() {
        let normal = abs(ScrollPhysics.velocity(initialVelocity: 1500, rate: .normal, at: 0.2))
        let fast = abs(ScrollPhysics.velocity(initialVelocity: 1500, rate: .fast, at: 0.2))

        #expect(fast < normal)
    }

    @Test("position matches the numerical integral of velocity")
    func positionMatchesIntegralOfVelocity() {
        // Integrate velocity with small steps and compare against the closed-form position.
        let v0 = 1800.0
        let steps = 2000
        let totalTime = 0.3
        let dt = totalTime / Double(steps)

        var numericPosition = 0.0
        var t = 0.0
        for _ in 0..<steps {
            numericPosition += ScrollPhysics.velocity(initialVelocity: v0, rate: .normal, at: t) * dt
            t += dt
        }

        let closedForm = ScrollPhysics.position(initialPosition: 0, initialVelocity: v0, rate: .normal, at: totalTime)

        #expect(abs(numericPosition - closedForm) < 1.0)
    }

    @Test("position approaches the resting position as time grows")
    func positionApproachesRestingPosition() {
        let resting = ScrollPhysics.restingPosition(initialPosition: 0, initialVelocity: 1500, rate: .normal)
        let late = ScrollPhysics.position(initialPosition: 0, initialVelocity: 1500, rate: .normal, at: 10)

        #expect(abs(late - resting) < 0.01)
    }

    @Test("velocity at timeToRest has decayed to restVelocity")
    func velocityAtTimeToRestMatchesThreshold() {
        let t = ScrollPhysics.timeToRest(initialVelocity: 1500, rate: .normal)
        let v = ScrollPhysics.velocity(initialVelocity: 1500, rate: .normal, at: t)

        #expect(abs(v - ScrollPhysics.restVelocity) < 0.01)
    }

    @Test("timeToRest is zero when already below the rest threshold")
    func timeToRestIsZeroWhenAlreadySlow() {
        let t = ScrollPhysics.timeToRest(initialVelocity: 1, rate: .normal)

        #expect(t == 0)
    }

    @Test("zero initial velocity never moves the position")
    func zeroVelocityDoesNotMove() {
        let x = ScrollPhysics.position(initialPosition: 42, initialVelocity: 0, rate: .normal, at: 10)

        #expect(x == 42)
    }
}

@Suite("ScrollPhysics.RubberBand")
struct ScrollPhysicsRubberBandTests {

    @Test("zero overscroll produces zero displacement")
    func zeroOverscrollIsZero() {
        #expect(ScrollPhysics.rubberBand(x: 0, dimension: 400) == 0)
    }

    @Test("displacement is monotonically increasing in the overscroll distance")
    func displacementIncreasesMonotonically() {
        let samples = stride(from: 0.0, through: 2000.0, by: 50.0).map {
            ScrollPhysics.rubberBand(x: $0, dimension: 400)
        }

        for (previous, next) in zip(samples, samples.dropFirst()) {
            #expect(next > previous)
        }
    }

    @Test("displacement never reaches the viewport dimension")
    func displacementStaysBelowDimension() {
        let huge = ScrollPhysics.rubberBand(x: 1_000_000, dimension: 400)

        #expect(huge < 400)
        #expect(huge > 399)
    }

    @Test("inverseRubberBand round-trips rubberBand")
    func inverseRoundTrips() {
        let x = 250.0
        let displacement = ScrollPhysics.rubberBand(x: x, dimension: 400)
        let recovered = ScrollPhysics.inverseRubberBand(displacement: displacement, dimension: 400)

        #expect(abs(recovered - x) < 0.001)
    }
}

@Suite("ScrollPhysics.Spring")
struct ScrollPhysicsSpringTests {

    @Test("a spring already at its target with no velocity is at rest")
    func atTargetIsAtRest() {
        let spring = ScrollPhysics.Spring(position: 10, velocity: 0, target: 10)

        #expect(spring.isAtRest)
    }

    @Test("a displaced spring eventually settles at its target")
    func displacedSpringSettles() {
        var spring = ScrollPhysics.Spring(position: 100, velocity: 0, target: 0)

        for _ in 0..<2000 {
            spring.step(dt: 1.0 / 120.0)
        }

        #expect(spring.isAtRest)
    }

    @Test("a critically damped spring never overshoots its target")
    func springDoesNotOvershoot() {
        var spring = ScrollPhysics.Spring(position: 100, velocity: 0, target: 0)

        for _ in 0..<2000 {
            spring.step(dt: 1.0 / 120.0)
            #expect(spring.position >= 0)
            #expect(spring.position <= 100)
        }
    }
}
