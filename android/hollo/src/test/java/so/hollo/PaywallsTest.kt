package so.hollo

import org.junit.Assert.assertEquals
import org.junit.Test

class PaywallsTest {
    @Test
    fun reportsOnlyTheFirstResult() {
        val results = mutableListOf<HolloPaywallResult>()
        runPaywall({ ref, done ->
            assertEquals("winback", ref)
            done(HolloPaywallResult.Purchased)
            done(HolloPaywallResult.Declined)
        }, "winback") { results.add(it) }
        assertEquals(listOf(HolloPaywallResult.Purchased), results)
    }

    @Test
    fun turnsAnExceptionIntoFailed() {
        val results = mutableListOf<HolloPaywallResult>()
        runPaywall({ _, _ -> throw IllegalStateException("no network") }, "x") { results.add(it) }
        assertEquals(listOf(HolloPaywallResult.Failed), results)
    }
}
