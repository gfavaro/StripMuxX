import unittest

from script import analyze_gesture_trace as a


def trace(inputs, changes):
    return {'seconds': 10, 'inputs': inputs, 'windowChanges': changes}


def pan(t, offset, origin=None):
    step = {'t': t, 'kind': 'pan', 'delta': 0, 'offset': offset}
    if origin is not None:
        step['from'] = origin
    return step


def end(t):
    return {'t': t, 'kind': 'end', 'delta': 0, 'offset': 0}


class AnalyseGestureTraceTest(unittest.TestCase):
    def test_a_window_that_follows_by_two_frames_has_a_small_lag(self):
        inputs = [pan(100 + 16 * i, 100 * i, 0 if i == 1 else None) for i in range(1, 9)] + [end(300)]
        changes = [[0, 1, 'App', 1000, 0, 800, 600]] + [
            [100 + 16 * i + 33, 1, 'App', 1000 - 100 * i, 0, 800, 600] for i in range(1, 9)]
        rows = a.analyse(trace(inputs, changes))
        lags = [v for vs in rows[0]['lags'].values() for v in vs]
        self.assertEqual(len(lags), 8)
        self.assertTrue(all(abs(v - 33) < 1 for v in lags), lags)

    def test_moves_after_the_next_gesture_starts_are_not_attributed_to_the_first(self):
        first = [pan(100 + 16 * i, 100 * i, 0 if i == 1 else None) for i in range(1, 9)] + [end(250)]
        second = [pan(300 + 16 * i, 800 + 100 * i, 800 if i == 1 else None) for i in range(1, 9)] + [end(500)]
        changes = [[0, 1, 'App', 3000, 0, 800, 600]]
        changes += [[100 + 16 * i + 20, 1, 'App', 3000 - 100 * i, 0, 800, 600] for i in range(1, 9)]
        # The second gesture's moves begin 50 ms after the first one's `end`.
        changes += [[300 + 16 * i + 20, 1, 'App', 3000 - 800 - 100 * i, 0, 800, 600] for i in range(1, 9)]
        rows = a.analyse(trace(first + second, changes))
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(v < 40 for vs in rows[0]['lags'].values() for v in vs), rows[0]['lags'])
        self.assertTrue(all(v < 40 for vs in rows[1]['lags'].values() for v in vs), rows[1]['lags'])
        self.assertLess(rows[0]['settle'], 250 - 100)

    def test_a_window_that_does_not_travel_with_the_strip_is_ignored(self):
        inputs = [pan(100 + 16 * i, 100 * i) for i in range(1, 9)] + [end(300)]
        changes = [[0, 1, 'Parked', -900, 0, 800, 600]] + [
            [100 + 16 * i, 1, 'Parked', -900 - i, 0, 800, 600] for i in range(1, 9)]
        rows = a.analyse(trace(inputs, changes))
        self.assertEqual(rows[0]['moved'], 0)

    def test_border_pieces_are_compared_with_the_nearest_window_edge(self):
        changes = [[0, 1, 'App', 100, 0, 800, 600],
                   [110, 2, 'StripMuxX', 96, 0, 5, 700],      # exactly on the left edge (x - 4)
                   [120, 3, 'StripMuxX', 150, 0, 5, 700]]      # 54 pt away (150 - 96)
        inputs = [pan(100, 10), pan(130, 20), end(200)]
        rows = a.analyse(trace(inputs, changes))
        self.assertEqual(sorted(rows[0]['border']), [0, 54])

    def test_report_runs_on_an_empty_trace(self):
        self.assertEqual(a.report(a.analyse(trace([], []))), '')


if __name__ == '__main__':
    unittest.main()
